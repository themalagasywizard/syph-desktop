import AppKit
import SwiftUI
import Observation

/// The desktop widget: the Syph orb, anywhere on screen. Click it and it opens
/// into a small chat with one employee, without bringing up the main window or
/// taking focus from the app you're in (the panel never activates Syph).
///
/// The orb stays exactly where the owner put it; the chat grows from it toward
/// the middle of the screen, so it works in any corner.
@MainActor
@Observable
final class DesktopWidget {
    static let orb: CGFloat = 60
    static let pad: CGFloat = 10
    static var collapsedSide: CGFloat { orb + pad * 2 }
    static let chatSize = CGSize(width: 380, height: 540)

    /// Which corner of the chat the orb sits in.
    enum Corner { case topLeading, topTrailing, bottomLeading, bottomTrailing
        var isTop: Bool { self == .topLeading || self == .topTrailing }
        var isLeading: Bool { self == .topLeading || self == .bottomLeading }
        var alignment: Alignment {
            switch self {
            case .topLeading: return .topLeading
            case .topTrailing: return .topTrailing
            case .bottomLeading: return .bottomLeading
            case .bottomTrailing: return .bottomTrailing
            }
        }
    }

    private(set) var isVisible = false
    /// Drives the open/close animation; the window resizes around it.
    private(set) var expanded = false
    private(set) var corner: Corner = .topLeading
    var employeeID: String?
    /// The app the owner is working in (updated as they switch apps while the chat is open).
    private(set) var context: FrontmostContext?
    var includeContext = true
    var draft = ""

    var startsInWidget: Bool {
        get { access(keyPath: \.startsInWidget); return UserDefaults.standard.bool(forKey: Keys.startsInWidget) }
        set { withMutation(keyPath: \.startsInWidget) { UserDefaults.standard.set(newValue, forKey: Keys.startsInWidget) } }
    }

    @ObservationIgnored private var panel: WidgetPanel?
    @ObservationIgnored private var dragOrigin: (mouse: NSPoint, frame: NSRect)?
    @ObservationIgnored private var appObserver: NSObjectProtocol?
    @ObservationIgnored private var animationToken = 0
    @ObservationIgnored weak var app: AppModel?

    private enum Keys {
        static let anchor = "syph.widget.anchor"
        static let visible = "syph.widget.visible"
        static let startsInWidget = "syph.widget.startsInWidget"
    }

    // MARK: Showing

    /// Brings the orb back where the owner left it (called at launch).
    func restore() {
        if UserDefaults.standard.bool(forKey: Keys.visible) { show(expand: false) }
    }

    func show(expand: Bool) {
        let panel = ensurePanel()
        if !isVisible {
            panel.setFrame(collapsedFrame(around: anchor), display: true)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; panel.animator().alphaValue = 1 }
            isVisible = true
            UserDefaults.standard.set(true, forKey: Keys.visible)
        }
        if expand { self.expand() }
    }

    func hide() {
        guard let panel, isVisible else { return }
        collapse(then: {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; panel.animator().alphaValue = 0 }) {
                Task { @MainActor in panel.orderOut(nil) }
            }
        })
        isVisible = false
        UserDefaults.standard.set(false, forKey: Keys.visible)
    }

    func toggle() {
        if !isVisible { show(expand: true) } else if expanded { collapse() } else { expand() }
    }

    // MARK: Expanding

    func expand() {
        guard let panel, !expanded else { panel?.makeKey(); return }
        context = FrontmostContext.capture() ?? context
        if employeeID == nil || app?.store.employee(employeeID) == nil { employeeID = app?.store.selectedEmployee?.id }
        let anchor = self.anchor
        corner = Self.corner(for: anchor, on: screen(for: anchor))
        animationToken += 1
        // Grow the window first with the orb in the same spot, then let SwiftUI reveal the chat.
        panel.setFrame(expandedFrame(around: anchor, corner: corner), display: true)
        withAnimation(.spring(response: 0.52, dampingFraction: 0.82)) { expanded = true }
        panel.makeKey()
        watchFrontmostApp()
    }

    func collapse(then done: (() -> Void)? = nil) {
        guard let panel, expanded else { done?(); return }
        withAnimation(.spring(response: 0.38, dampingFraction: 0.9)) { expanded = false }
        animationToken += 1
        let token = animationToken
        stopWatchingFrontmostApp()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            guard token == self.animationToken else { return }
            panel.setFrame(self.collapsedFrame(around: self.anchor), display: true)
            // Hand the keyboard back to whatever the owner was using.
            panel.resignKey()
            done?()
        }
    }

    // MARK: Switching between the widget and the app

    /// From the widget to the full app, on the same employee and conversation.
    func openApp() {
        guard let app else { return }
        if let employee = app.store.employee(employeeID) { app.store.select(employee) }
        if !draft.isEmpty, let id = employeeID { app.store.drafts[id] = draft; draft = "" }
        collapse()
        app.showMainWindow(section: .chat)
    }

    /// From the full app to the widget: the main window steps aside and the chat opens.
    func enterFromApp() {
        guard let app else { return }
        employeeID = app.store.selectedEmployee?.id
        app.hideMainWindow()
        show(expand: true)
    }

    func cycle(_ step: Int) {
        guard let store = app?.store, !store.employees.isEmpty else { return }
        let index = store.employees.firstIndex { $0.id == employeeID } ?? 0
        let next = store.employees[(index + step + store.employees.count) % store.employees.count]
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { employeeID = next.id }
        store.select(next)
    }

    // MARK: Sending

    func send() async {
        guard let app, let id = employeeID else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        let body = includeContext && context != nil ? "\(text)\n\n\(context!.note)" : text
        draft = ""
        if !(await app.store.send(body, to: id)) { draft = text }
    }

    // MARK: Dragging

    func beginDrag() {
        guard let panel else { return }
        dragOrigin = (NSEvent.mouseLocation, panel.frame)
    }

    func drag() {
        guard let panel, let origin = dragOrigin else { return }
        let now = NSEvent.mouseLocation
        panel.setFrameOrigin(NSPoint(x: origin.frame.minX + now.x - origin.mouse.x, y: origin.frame.minY + now.y - origin.mouse.y))
    }

    func endDrag() {
        guard let panel, dragOrigin != nil else { return }
        dragOrigin = nil
        // Keep the whole orb on a screen, and remember where it lives.
        let center = orbCenter(in: panel.frame)
        let visible = screen(for: center).visibleFrame.insetBy(dx: Self.collapsedSide / 2, dy: Self.collapsedSide / 2)
        let clamped = CGPoint(x: min(max(center.x, visible.minX), visible.maxX), y: min(max(center.y, visible.minY), visible.maxY))
        anchor = clamped
        let target = expanded ? expandedFrame(around: clamped, corner: corner) : collapsedFrame(around: clamped)
        if target != panel.frame {
            NSAnimationContext.runAnimationGroup { $0.duration = 0.18; panel.animator().setFrame(target, display: true) }
        }
    }

    // MARK: Geometry

    /// Screen point of the orb's centre, saved across launches.
    private var anchor: CGPoint {
        get {
            if let saved = UserDefaults.standard.string(forKey: Keys.anchor) {
                let point = NSPointFromString(saved)
                if NSScreen.screens.contains(where: { $0.visibleFrame.contains(point) }) { return point }
            }
            let frame = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
            return CGPoint(x: frame.maxX - 70, y: frame.minY + 110)
        }
        set { UserDefaults.standard.set(NSStringFromPoint(newValue), forKey: Keys.anchor) }
    }

    private func screen(for point: CGPoint) -> NSScreen {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    /// The chat opens toward the middle of the screen from wherever the orb is.
    private static func corner(for point: CGPoint, on screen: NSScreen) -> Corner {
        let f = screen.visibleFrame
        let right = point.x > f.midX
        let upper = point.y > f.midY   // AppKit's y grows upward
        switch (upper, right) {
        case (true, false): return .topLeading
        case (true, true): return .topTrailing
        case (false, false): return .bottomLeading
        case (false, true): return .bottomTrailing
        }
    }

    private func collapsedFrame(around center: CGPoint) -> NSRect {
        let side = Self.collapsedSide
        return NSRect(x: center.x - side / 2, y: center.y - side / 2, width: side, height: side)
    }

    private func expandedFrame(around center: CGPoint, corner: Corner) -> NSRect {
        let size = Self.chatSize
        let inset = Self.pad + Self.orb / 2
        let x = corner.isLeading ? center.x - inset : center.x + inset - size.width
        let y = corner.isTop ? center.y + inset - size.height : center.y - inset
        return NSRect(x: x, y: y, width: size.width, height: size.height)
    }

    private func orbCenter(in frame: NSRect) -> CGPoint {
        guard expanded else { return CGPoint(x: frame.midX, y: frame.midY) }
        let inset = Self.pad + Self.orb / 2
        return CGPoint(x: corner.isLeading ? frame.minX + inset : frame.maxX - inset,
                       y: corner.isTop ? frame.maxY - inset : frame.minY + inset)
    }

    #if DEBUG
    /// Design review without Screen Recording permission: renders the widget's own window to a PNG.
    func snapshot(to path: String) {
        guard let view = panel?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
    }
    #endif

    // MARK: Plumbing

    private func ensurePanel() -> WidgetPanel {
        if let panel { return panel }
        let panel = WidgetPanel(size: CGSize(width: Self.collapsedSide, height: Self.collapsedSide))
        if let app {
            panel.host(DesktopWidgetView().environment(app).environment(app.store).environment(self))
        }
        panel.onEscape = { [weak self] in self?.collapse() }
        self.panel = panel
        return panel
    }

    private func watchFrontmostApp() {
        guard appObserver == nil else { return }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            guard let running = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let context = FrontmostContext(app: running) else { return }
            Task { @MainActor in self?.context = context }
        }
    }

    private func stopWatchingFrontmostApp() {
        if let appObserver { NSWorkspace.shared.notificationCenter.removeObserver(appObserver) }
        appObserver = nil
    }
}

/// A borderless panel that floats above apps on every Space, takes typing
/// without activating Syph, and never becomes a main window.
final class WidgetPanel: NSPanel {
    var onEscape: (() -> Void)?

    init(size: CGSize) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .floating
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        becomesKeyOnlyIfNeeded = false
        isMovable = false // the orb and the header move it, so text selection still works
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func cancelOperation(_ sender: Any?) { onEscape?() }

    func host<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: view.appAppearance())
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        hosting.layer?.backgroundColor = .clear
        contentView = hosting
    }
}

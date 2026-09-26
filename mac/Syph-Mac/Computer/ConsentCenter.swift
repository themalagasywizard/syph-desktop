import AppKit
import SwiftUI
import Observation

/// A floating, non-activating panel: it never steals focus from the app the
/// employee is working in, but always sits above it.
final class FloatingPanel: NSPanel {
    init(size: CGSize, clickThrough: Bool = false) {
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .statusBar
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = clickThrough
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isMovableByWindowBackground = false
    }

    override var canBecomeKey: Bool { !ignoresMouseEvents }
    override var canBecomeMain: Bool { false }

    func host<V: View>(_ view: V) {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: frame.size)
        hosting.autoresizingMask = [.width, .height]
        contentView = hosting
    }
}

struct ConsentRequest: Identifiable, Equatable {
    let id = UUID()
    let employee: String
    let scope: ComputerScope
    let operation: String
    let headline: String
    let detail: String
    let deadline: Date
}

enum ConsentDecision { case once, always, deny }

/// Asks the owner before an ask-first scope runs.
@MainActor
@Observable
final class ConsentCenter {
    private(set) var current: ConsentRequest?
    @ObservationIgnored private var continuation: CheckedContinuation<ConsentDecision, Never>?
    @ObservationIgnored private var panel: FloatingPanel?
    @ObservationIgnored private var timeoutTask: Task<Void, Never>?

    static let timeout: TimeInterval = 60

    func ask(employee: String, scope: ComputerScope, command: DeviceCommand) async -> ConsentDecision {
        // One question at a time; a second request while one is open is declined.
        guard continuation == nil else { return .deny }
        let request = ConsentRequest(
            employee: employee.isEmpty ? "An employee" : employee,
            scope: scope,
            operation: command.operation,
            headline: Self.headline(command),
            detail: Self.detail(command),
            deadline: Date().addingTimeInterval(Self.timeout)
        )
        current = request
        present()
        NSSound(named: "Tink")?.play()
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(Self.timeout))
                guard !Task.isCancelled else { return }
                self?.decide(.deny)
            }
        }
    }

    func decide(_ decision: ConsentDecision) {
        timeoutTask?.cancel()
        timeoutTask = nil
        let continuation = continuation
        self.continuation = nil
        withAnimation(Motion.snappy) { current = nil }
        panel?.orderOut(nil)
        continuation?.resume(returning: decision)
    }

    private func present() {
        let size = CGSize(width: 440, height: 400)
        if panel == nil {
            let panel = FloatingPanel(size: size)
            panel.host(ConsentPanelView(center: self))
            self.panel = panel
        }
        guard let panel, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        // Below the driving pill, so both stay readable on small screens.
        panel.setFrameOrigin(NSPoint(x: frame.maxX - size.width - 16, y: frame.maxY - size.height - 64))
        panel.orderFrontRegardless()
    }

    static func headline(_ command: DeviceCommand) -> String {
        switch command.operation {
        case "run_shell": return "Run a terminal command"
        case "applescript": return "Run an AppleScript"
        case "write_file": return "Write \(URL(fileURLWithPath: command.string("path") ?? "a file").lastPathComponent)"
        case "trash_file": return "Move \(URL(fileURLWithPath: command.string("path") ?? "a file").lastPathComponent) to the Trash"
        case "type_text": return "Type into \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "the front app")"
        case "press_keys": return "Press \(command.string("keys") ?? "a shortcut")"
        case "click", "click_text": return "Click \(command.string("text").map { "“\($0)”" } ?? "on screen")"
        case "press": return "Press “\(command.string("title") ?? "a button")”"
        case "open_app": return "Open \(command.string("app") ?? "an app")"
        case "quit_app": return "Quit \(command.string("app") ?? "an app")"
        case "open_url": return "Open \(URL(string: command.string("url") ?? "")?.host ?? "a link")"
        case "read_screen", "read_ui": return "Read your screen"
        default: return command.operation.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    static func detail(_ command: DeviceCommand) -> String {
        command.string("command") ?? command.string("script") ?? command.string("text")
            ?? command.string("path") ?? command.string("url") ?? command.string("keys") ?? ""
    }
}

private struct ConsentPanelView: View {
    let center: ConsentCenter

    var body: some View {
        ZStack {
            if let request = center.current {
                ConsentCard(request: request) { center.decide($0) }
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: 440, height: 400, alignment: .top)
        .preferredColorScheme(.dark)
    }
}

private struct ConsentCard: View {
    let request: ConsentRequest
    let decide: (ConsentDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                AgentOrb(mood: .attention, tint: Palette.amber, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(request.employee) wants to").font(Typo.caption).foregroundStyle(Palette.textSecondary)
                    Text(request.headline).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.text).lineLimit(2)
                }
                Spacer()
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    let left = max(0, Int(request.deadline.timeIntervalSince(context.date)))
                    Text("\(left)s").font(Typo.mono).foregroundStyle(Palette.textTertiary)
                }
            }
            if !request.detail.isEmpty {
                ScrollView {
                    Text(request.detail)
                        .font(Typo.mono)
                        .foregroundStyle(Palette.text.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 90)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.4)))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.hairline, lineWidth: 0.75))
            }
            HStack(spacing: 6) {
                Image(systemName: request.scope.symbol)
                Text("Scope: \(request.scope.title)")
                Spacer()
            }
            .font(Typo.caption)
            .foregroundStyle(Palette.textTertiary)
            HStack(spacing: 8) {
                Button("Decline") { decide(.deny) }
                    .buttonStyle(GhostButtonStyle(tint: Palette.coral))
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Always allow") { decide(.always) }
                    .buttonStyle(GhostButtonStyle())
                Button("Allow once") { decide(.once) }
                    .buttonStyle(SignalButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .background(
            ZStack {
                VisualEffect(material: .hudWindow)
                Palette.void.opacity(0.55)
            }
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Palette.amber.opacity(0.6), Palette.hairline], startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: 12)
        .padding(12)
    }
}

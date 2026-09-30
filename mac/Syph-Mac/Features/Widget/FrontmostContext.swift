import AppKit
import ApplicationServices

/// The app (and, with Accessibility, the window) the owner is using while they
/// talk to the widget, so "do this here" means something to the employee.
struct FrontmostContext: Equatable {
    let appName: String
    let bundleID: String
    let windowTitle: String?
    let icon: NSImage?

    static func == (a: FrontmostContext, b: FrontmostContext) -> Bool {
        a.bundleID == b.bundleID && a.windowTitle == b.windowTitle
    }

    /// The frontmost app other than Syph, or nil when Syph itself is in front.
    static func capture() -> FrontmostContext? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.bundleIdentifier != Bundle.main.bundleIdentifier else { return nil }
        return FrontmostContext(app: app)
    }

    init?(app: NSRunningApplication) {
        guard app.bundleIdentifier != Bundle.main.bundleIdentifier, app.activationPolicy == .regular else { return nil }
        appName = app.localizedName ?? "this app"
        bundleID = app.bundleIdentifier ?? ""
        icon = app.icon
        windowTitle = Self.focusedWindowTitle(pid: app.processIdentifier)
    }

    /// Needs the Accessibility permission Syph already asks for computer control; nil without it.
    private static func focusedWindowTitle(pid: pid_t) -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let element = AXUIElementCreateApplication(pid)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window as! AXUIElement, kAXTitleAttribute as CFString, &title) == .success,
              let text = title as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : String(trimmed.prefix(120))
    }

    /// One line appended to the message, written for the employee.
    var note: String {
        let window = windowTitle.map { " — “\($0)”" } ?? ""
        return "(Sent from the Syph widget while I’m using \(appName)\(window) on this Mac. “Here” and “this” mean that.)"
    }

    var label: String { windowTitle.map { "\(appName) · \($0)" } ?? appName }
}

import Foundation
import AppKit
import ApplicationServices
import Observation

/// What an employee may do on this Mac. Every command belongs to one scope; the
/// owner sets each scope to Off, Ask first, or Allow. Raw values are shared
/// with the server (`app/runtime/computer_tool.py`).
enum ComputerScope: String, CaseIterable, Identifiable, Codable {
    case observe, screen, control, apps, clipboard
    case filesRead = "files_read"
    case filesWrite = "files_write"
    case automation, shell

    var id: String { rawValue }

    var title: String {
        switch self {
        case .observe: return "See what’s open"
        case .screen: return "Read the screen"
        case .control: return "Click and type"
        case .apps: return "Open apps and links"
        case .clipboard: return "Clipboard"
        case .filesRead: return "Read shared files"
        case .filesWrite: return "Change shared files"
        case .automation: return "Automate apps (AppleScript)"
        case .shell: return "Run terminal commands"
        }
    }

    var detail: String {
        switch self {
        case .observe: return "Frontmost app, window titles, running apps."
        case .screen: return "On-device text recognition of the screen and window controls. Nothing leaves the Mac but the text."
        case .control: return "Move the pointer, click, type and press shortcuts while you watch."
        case .apps: return "Launch, focus and quit apps; open links in your browser."
        case .clipboard: return "Read and write the clipboard."
        case .filesRead: return "List and read files, only inside the folders you share below."
        case .filesWrite: return "Create, overwrite and trash files inside shared folders."
        case .automation: return "Drive Mail, Calendar, Finder, Numbers and other scriptable apps."
        case .shell: return "Run zsh commands as you. The most powerful scope — keep it on Ask."
        }
    }

    var symbol: String {
        switch self {
        case .observe: return "eye"
        case .screen: return "text.viewfinder"
        case .control: return "cursorarrow.click.2"
        case .apps: return "square.grid.2x2"
        case .clipboard: return "doc.on.clipboard"
        case .filesRead: return "folder"
        case .filesWrite: return "folder.badge.plus"
        case .automation: return "applescript"
        case .shell: return "terminal"
        }
    }

    var risk: Int {
        switch self {
        case .observe, .clipboard: return 0
        case .screen, .apps, .filesRead: return 1
        case .control, .filesWrite, .automation: return 2
        case .shell: return 3
        }
    }

    /// Which macOS privacy permission the scope depends on, if any.
    var systemRequirement: SystemPermission? {
        switch self {
        case .screen: return .screenRecording
        case .control: return .accessibility
        case .observe: return nil
        default: return nil
        }
    }

    static func forOperation(_ operation: String) -> ComputerScope? {
        switch operation {
        case "observe", "notify": return .observe
        case "read_screen", "read_ui": return .screen
        case "click", "click_text", "press", "type_text", "press_keys", "scroll": return .control
        case "open_app", "quit_app", "open_url": return .apps
        case "list_files", "read_file": return .filesRead
        case "write_file", "trash_file": return .filesWrite
        case "run_shell": return .shell
        case "applescript": return .automation
        case "clipboard_read", "clipboard_write": return .clipboard
        default: return nil
        }
    }

    var defaultMode: ScopeMode {
        switch self {
        case .observe, .screen, .apps, .filesRead, .clipboard: return .allow
        case .control, .filesWrite, .automation, .shell: return .ask
        }
    }
}

enum ScopeMode: String, CaseIterable, Codable, Identifiable {
    case off, ask, allow
    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .ask: return "Ask"
        case .allow: return "Allow"
        }
    }
}

enum SystemPermission: String, CaseIterable, Identifiable {
    case accessibility, screenRecording, automation

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .screenRecording: return "Screen Recording"
        case .automation: return "Automation"
        }
    }

    var detail: String {
        switch self {
        case .accessibility: return "Needed to click, type and read window controls."
        case .screenRecording: return "Needed to read text on screen."
        case .automation: return "macOS asks per app the first time a script drives it."
        }
    }

    var settingsURL: URL? {
        switch self {
        case .accessibility: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .screenRecording: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        case .automation: return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        }
    }

    var isGranted: Bool {
        switch self {
        case .accessibility: return AXIsProcessTrusted()
        case .screenRecording: return CGPreflightScreenCaptureAccess()
        case .automation: return true
        }
    }

    func request() {
        switch self {
        case .accessibility:
            // "AXTrustedCheckOptionPrompt" is kAXTrustedCheckOptionPrompt; its Swift import differs across SDKs.
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        case .screenRecording:
            _ = CGRequestScreenCaptureAccess()
        case .automation:
            break
        }
        if let url = settingsURL, !isGranted { NSWorkspace.shared.open(url) }
    }
}

/// The owner's local choices, persisted on this Mac only.
@MainActor
@Observable
final class ComputerPolicy {
    private static let modesKey = "syph.computer.modes"
    private static let foldersKey = "syph.computer.folders"
    private static let enabledKey = "syph.computer.enabled"

    var controlEnabled: Bool {
        didSet { UserDefaults.standard.set(controlEnabled, forKey: Self.enabledKey); onChange?() }
    }
    var modes: [ComputerScope: ScopeMode] {
        didSet { persistModes(); onChange?() }
    }
    var sharedFolders: [URL] {
        didSet { UserDefaults.standard.set(sharedFolders.map(\.path), forKey: Self.foldersKey) }
    }
    /// Refreshed on demand so the UI reflects changes made in System Settings.
    var systemGrants: [SystemPermission: Bool] = [:]

    @ObservationIgnored var onChange: (() -> Void)?

    init() {
        controlEnabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        var modes: [ComputerScope: ScopeMode] = [:]
        let stored = UserDefaults.standard.dictionary(forKey: Self.modesKey) as? [String: String] ?? [:]
        for scope in ComputerScope.allCases {
            modes[scope] = stored[scope.rawValue].flatMap(ScopeMode.init(rawValue:)) ?? scope.defaultMode
        }
        self.modes = modes
        let paths = UserDefaults.standard.stringArray(forKey: Self.foldersKey)
        if let paths {
            sharedFolders = paths.map { URL(fileURLWithPath: $0, isDirectory: true) }
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            sharedFolders = [home.appendingPathComponent("Documents/Syph", isDirectory: true)]
            try? FileManager.default.createDirectory(at: sharedFolders[0], withIntermediateDirectories: true)
        }
        refreshSystemGrants()
    }

    func mode(_ scope: ComputerScope) -> ScopeMode { modes[scope] ?? scope.defaultMode }

    func set(_ scope: ComputerScope, _ mode: ScopeMode) { modes[scope] = mode }

    var wireScopes: [String: String] {
        Dictionary(uniqueKeysWithValues: ComputerScope.allCases.map { ($0.rawValue, mode($0).rawValue) })
    }

    func refreshSystemGrants() {
        var grants: [SystemPermission: Bool] = [:]
        for permission in SystemPermission.allCases { grants[permission] = permission.isGranted }
        systemGrants = grants
    }

    func addFolder(_ url: URL) {
        let standardized = url.standardizedFileURL
        guard !sharedFolders.contains(where: { $0.standardizedFileURL.path == standardized.path }) else { return }
        sharedFolders.append(standardized)
    }

    func removeFolder(_ url: URL) {
        sharedFolders.removeAll { $0.path == url.path }
    }

    /// Resolves a path the agent gave and returns it only if it sits inside a shared folder.
    func resolveShared(_ raw: String?) -> URL? {
        guard let raw, !raw.isEmpty else { return nil }
        let expanded = (raw as NSString).expandingTildeInPath
        let candidate: URL
        if expanded.hasPrefix("/") {
            candidate = URL(fileURLWithPath: expanded)
        } else if let first = sharedFolders.first {
            candidate = first.appendingPathComponent(expanded)
        } else {
            return nil
        }
        let resolved = candidate.standardizedFileURL.resolvingSymlinksInPath().path
        for folder in sharedFolders {
            let root = folder.standardizedFileURL.resolvingSymlinksInPath().path
            if resolved == root || resolved.hasPrefix(root.hasSuffix("/") ? root : root + "/") {
                return URL(fileURLWithPath: resolved)
            }
        }
        return nil
    }

    private func persistModes() {
        UserDefaults.standard.set(wireScopes, forKey: Self.modesKey)
    }
}

import AppKit
import SwiftUI
import Observation
import UserNotifications

enum AppSection: String, CaseIterable, Identifiable {
    case chat, team, approvals, work, library, computer, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .chat: return "Command"
        case .team: return "Team"
        case .approvals: return "Needs you"
        case .work: return "Work"
        case .library: return "Library"
        case .computer: return "This Mac"
        case .settings: return "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .chat: return "bubble.left.and.text.bubble.right"
        case .team: return "person.2"
        case .approvals: return "checkmark.seal"
        case .work: return "waveform.path.ecg"
        case .library: return "books.vertical"
        case .computer: return "desktopcomputer"
        case .settings: return "slider.horizontal.3"
        }
    }

    var shortcut: KeyEquivalent {
        KeyEquivalent(Character(String((AppSection.allCases.firstIndex(of: self) ?? 0) + 1)))
    }
}

@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    let api = APIClient()
    let store: WorkspaceStore
    let policy = ComputerPolicy()
    let bridge: DeviceBridge

    var section: AppSection = .chat
    var showHire = false
    var openDocumentID: String?

    @ObservationIgnored private var commandBar: FloatingPanel?
    @ObservationIgnored private var commandBarMonitor: Any?
    @ObservationIgnored private var seenApprovals: Set<String> = []
    @ObservationIgnored private var didPrimeApprovals = false

    private init() {
        store = WorkspaceStore(api: api)
        bridge = DeviceBridge(api: api, policy: policy)
        store.onRefresh = { [weak self] in self?.workspaceRefreshed() }
    }

    func launch() async {
        if DemoMode.isOn { launchDemo(); return }
        #if DEBUG
        // Automation hook for the end-to-end CI job; compiled out of Release.
        let defaults = UserDefaults.standard
        if let server = defaults.string(forKey: "SyphServer") { api.server = server }
        if let email = defaults.string(forKey: "SyphEmail"), let password = defaults.string(forKey: "SyphPassword") {
            for _ in 0..<10 where store.phase != .ready {
                await store.signIn(email: email, password: password)
                if store.phase != .ready { try? await Task.sleep(for: .seconds(3)) }
            }
            NSLog("Syph automation sign-in: %@", store.phase == .ready ? "ready" : (store.errorMessage ?? "failed"))
            if store.phase == .ready { bridge.start() }
            return
        }
        #endif
        await store.restore()
        if store.phase == .ready { bridge.start() }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    func signedIn() {
        bridge.start()
    }

    func signOut() async {
        bridge.stop()
        await store.signOut()
    }

    func go(_ section: AppSection) {
        withAnimation(Motion.snappy) { self.section = section }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.identifier?.rawValue.contains("main") == true }?.makeKeyAndOrderFront(nil)
    }

    // MARK: Notifications

    private func workspaceRefreshed() {
        let waiting = store.waitingApprovals
        let ids = Set(waiting.map(\.id))
        defer { seenApprovals = ids; didPrimeApprovals = true }
        guard didPrimeApprovals else { return }
        let fresh = waiting.filter { !seenApprovals.contains($0.id) }
        NSApp.dockTile.badgeLabel = waiting.isEmpty ? nil : "\(waiting.count)"
        guard !fresh.isEmpty, !NSApp.isActive else { return }
        for approval in fresh {
            let content = UNMutableNotificationContent()
            content.title = "\(store.employee(approval.employeeId)?.name ?? "An employee") needs you"
            content.body = approval.title
            content.sound = .default
            UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: approval.id, content: content, trigger: nil))
        }
    }

    // MARK: Command bar

    func toggleCommandBar() {
        if let panel = commandBar, panel.isVisible { hideCommandBar(); return }
        guard store.phase == .ready else { go(.chat); return }
        let size = CGSize(width: 680, height: 420)
        if commandBar == nil {
            let panel = FloatingPanel(size: size)
            panel.level = .modalPanel
            panel.host(CommandBarView(close: { [weak self] in self?.hideCommandBar() }).environment(self).environment(store))
            commandBar = panel
        }
        guard let panel = commandBar, let screen = NSScreen.main else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2, y: frame.maxY - size.height - frame.height * 0.16))
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .commandBarOpened, object: nil)
        commandBarMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hideCommandBar() }
        }
    }

    func hideCommandBar() {
        commandBar?.orderOut(nil)
        if let monitor = commandBarMonitor { NSEvent.removeMonitor(monitor); commandBarMonitor = nil }
    }
}

extension Notification.Name {
    static let commandBarOpened = Notification.Name("syph.commandBarOpened")
}

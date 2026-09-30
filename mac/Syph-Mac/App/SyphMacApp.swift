import SwiftUI
import AppKit

@main
struct SyphMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var app = AppModel.shared

    var body: some Scene {
        Window(Brand.name, id: "main") {
            RootView()
                .environment(app)
                .environment(app.store)
                .appAppearance()
                .frame(minWidth: 1040, minHeight: 660)
                .task { await app.launch() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        .defaultSize(width: 1320, height: 840)
        .commands { SyphCommands(app: app) }

        MenuBarExtra {
            MenuBarPanel()
                .environment(app)
                .environment(app.store)
                .appAppearance()
        } label: {
            MenuBarLabel(app: app)
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView()
                .environment(app)
                .environment(app.store)
                .appAppearance()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        HotKeyCenter.shared.register(key: HotKeyCenter.commandBar.key, modifiers: HotKeyCenter.commandBar.modifiers) {
            Task { @MainActor in AppModel.shared.toggleCommandBar() }
        }
        HotKeyCenter.shared.register(key: HotKeyCenter.killSwitch.key, modifiers: HotKeyCenter.killSwitch.modifiers) {
            Task { @MainActor in AppModel.shared.bridge.emergencyStop() }
        }
        HotKeyCenter.shared.register(key: HotKeyCenter.widget.key, modifiers: HotKeyCenter.widget.modifiers) {
            Task { @MainActor in AppModel.shared.widget.toggle() }
        }
    }

    /// Closing the window keeps Syph in the menu bar so employees can still reach this Mac.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct SyphCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Hire Employee…") { app.go(.team); app.showHire = true }
                .keyboardShortcut("n", modifiers: [.command])
        }
        CommandMenu("Go") {
            Button("Command Bar") { app.toggleCommandBar() }
                .keyboardShortcut("k", modifiers: [.command])
            Button("Widget Mode") { app.widget.enterFromApp() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
            Divider()
            ForEach(AppSection.allCases) { section in
                Button(section.title) { app.go(section) }
                    .keyboardShortcut(section.shortcut, modifiers: [.command])
            }
        }
        CommandMenu("Employees") {
            Button("Refresh") { Task { await app.store.refresh() } }
                .keyboardShortcut("r", modifiers: [.command])
            Button("Pause All Employees") { Task { await app.store.pauseAll() } }
                .keyboardShortcut("p", modifiers: [.command, .shift])
            Divider()
            Button(app.policy.controlEnabled ? "Stop Computer Control" : "Allow Computer Control") {
                if app.policy.controlEnabled { app.bridge.emergencyStop() } else { app.policy.controlEnabled = true }
            }
            .keyboardShortcut(".", modifiers: [.command, .option, .control])
        }
    }
}

struct MenuBarLabel: View {
    let app: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let waiting = app.store.waitingApprovals.count
        let driving = app.bridge.isRunning
        HStack(spacing: 3) {
            Image(systemName: driving ? "circle.hexagongrid.circle.fill" : (waiting > 0 ? "circle.circle.fill" : "circle.circle"))
            if waiting > 0 { Text("\(waiting)") }
        }
        // The menu bar label always exists, so it is where the widget gets a way to reopen the app.
        .onAppear { app.openMainWindow = { openWindow(id: "main") } }
    }
}

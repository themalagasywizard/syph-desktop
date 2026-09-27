import SwiftUI
import AppKit

struct SettingsScreen: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                ScreenHeader(eyebrow: "Settings", title: "Workspace").padding(.horizontal, -24)
                AccountSection()
                ModelSection()
                IntegrationsSection()
                ShortcutsSection()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 28)
            .frame(maxWidth: 820, alignment: .leading)
        }
    }
}

/// The ⌘, window shows the same controls.
struct PreferencesView: View {
    var body: some View {
        SettingsScreen()
            .frame(width: 720, height: 640)
            .background(Palette.void)
    }
}

private struct AccountSection: View {
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        SettingsGroup(title: "Account", symbol: "person.crop.circle") {
            if let user = store.user {
                row("Signed in as", "\(user.name) · \(user.email)")
                row("Role", user.role)
            }
            row("Server", app.api.server)
            row("This Mac", app.bridge.deviceID)
            HStack {
                Spacer()
                Button("Sign out") { Task { await app.signOut() } }.buttonStyle(GhostButtonStyle(tint: Palette.coral, compact: true))
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(Typo.callout).foregroundStyle(Palette.textTertiary).frame(width: 110, alignment: .leading)
            Text(value).font(Typo.callout).foregroundStyle(Palette.text).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
            Spacer()
        }
    }
}

private struct ModelSection: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var provider = ""
    @State private var model = ""
    @State private var apiKey = ""
    @State private var status: String?
    @State private var ok = false
    @State private var busy = false

    var body: some View {
        SettingsGroup(title: "AI model", symbol: "cpu") {
            let current = store.llmProviders.first { $0.id == provider }
            HStack(spacing: 12) {
                Picker("Provider", selection: $provider) {
                    ForEach(store.llmProviders) { Text($0.name).tag($0.id) }
                }
                Picker("Model", selection: $model) {
                    ForEach(current?.models ?? []) { Text($0.name).tag($0.id) }
                    if let custom = current, custom.allowCustomModel, !(custom.models.contains { $0.id == model }), !model.isEmpty {
                        Text(model).tag(model)
                    }
                }
            }
            SyphTextField(title: store.llmSettings?.keyConfigured == true ? "Key saved (\(store.llmSettings?.keyHint ?? "")) — paste to replace"
                                                                        : (current?.keyLabel ?? "API key"),
                          text: $apiKey, secure: true, symbol: "key")
            HStack {
                if let status {
                    Label(status, systemImage: ok ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(Typo.caption).foregroundStyle(ok ? Palette.mint : Palette.coral)
                }
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button("Test") { run { let r = try await store.testModel(); ok = r.ok; status = r.message } }
                    .buttonStyle(GhostButtonStyle(compact: true))
                Button("Save") {
                    run {
                        try await store.saveModel(provider: provider, model: model, apiKey: apiKey)
                        apiKey = ""; ok = true; status = "Saved."
                    }
                }
                .buttonStyle(SignalButtonStyle(compact: true))
                .disabled(provider.isEmpty || model.isEmpty)
            }
        }
        .task {
            await store.loadModelSettings()
            provider = store.llmSettings?.provider ?? store.llmProviders.first?.id ?? ""
            model = store.llmSettings?.model ?? ""
        }
        .onChange(of: provider) { _, value in
            if let first = store.llmProviders.first(where: { $0.id == value })?.models.first,
               !(store.llmProviders.first { $0.id == value }?.models.contains { $0.id == model } ?? false) {
                model = first.id
            }
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        busy = true
        status = nil
        Task {
            do { try await work() } catch { ok = false; status = error.localizedDescription }
            busy = false
        }
    }
}

private struct IntegrationsSection: View {
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store
    static let console = URL(string: "https://jarvis-client-console.netlify.app/settings")!

    var body: some View {
        SettingsGroup(title: "Connected tools", symbol: "point.3.connected.trianglepath.dotted") {
            ForEach(store.accountTools) { tool in
                HStack(spacing: 12) {
                    IntegrationMark(id: tool.id, size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(tool.name).font(Typo.callout).foregroundStyle(Palette.text)
                        Text(tool.description).font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                    }
                    Spacer()
                    Text(tool.connected ? "Connected" : "Not connected").font(Typo.caption)
                        .foregroundStyle(tool.connected ? Palette.mint : Palette.textTertiary)
                    if let service = googleService(tool.id), !tool.connected {
                        Button("Connect") { connectGoogle(service) }.buttonStyle(GhostButtonStyle(compact: true))
                    } else if tool.id == "computer" {
                        Button("Open") { app.go(.computer) }.buttonStyle(GhostButtonStyle(compact: true))
                    }
                }
                .padding(.vertical, 2)
            }
            HStack {
                Text("OAuth apps, WhatsApp, Telegram, Odoo and Etsy keys are managed in the web console.")
                    .font(Typo.caption).foregroundStyle(Palette.textTertiary)
                Spacer()
                Button("Open web console") { NSWorkspace.shared.open(Self.console) }.buttonStyle(GhostButtonStyle(compact: true))
            }
            .padding(.top, 6)
        }
    }

    private func googleService(_ id: String) -> String? {
        ["gmail": "gmail", "calendar": "calendar", "drive": "drive", "docs": "docs", "sheet": "sheet"][id]
    }

    private func connectGoogle(_ service: String) {
        Task {
            do {
                if let url = try await store.connectURL("/api/v1/settings/gmail/connect?service=\(service)") {
                    NSWorkspace.shared.open(url)
                }
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
    }
}

private struct ShortcutsSection: View {
    var body: some View {
        SettingsGroup(title: "Keyboard", symbol: "keyboard") {
            shortcut(["⌥", "Space"], "Command bar, from anywhere")
            shortcut(["⌃", "⌥", "⌘", "."], "Stop computer control, from anywhere")
            shortcut(["⌘", "K"], "Command bar")
            shortcut(["⌘", "1…7"], "Switch sections")
            shortcut(["⌘", "N"], "Hire an employee")
            shortcut(["⌘", "↩"], "Approve the open decision")
        }
    }

    private func shortcut(_ keys: [String], _ label: String) -> some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { KeyCap(key: $0) }
            Text(label).font(Typo.callout).foregroundStyle(Palette.textSecondary).padding(.leading, 8)
            Spacer()
        }
    }
}

struct SettingsGroup<Content: View>: View {
    let title: String
    let symbol: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(Typo.headline).foregroundStyle(Palette.text)
            VStack(alignment: .leading, spacing: 10) { content() }
        }
        .card(radius: 16, padding: 18)
    }
}

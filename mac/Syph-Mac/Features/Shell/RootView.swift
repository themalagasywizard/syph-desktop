import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        ZStack {
            Backdrop(intensity: store.phase == .ready ? 0.55 : 1)
            switch store.phase {
            case .restoring, .loading:
                LaunchGate(message: store.phase == .restoring ? "Restoring your session" : "Loading your workspace")
                    .transition(.opacity)
            case .signedOut:
                SignInView()
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
            case .ready:
                Shell()
                    .transition(.opacity)
            }
        }
        .animation(Motion.soft, value: store.phase)
        .onChange(of: store.phase) { _, phase in
            if phase == .ready { app.signedIn() }
        }
    }
}

struct LaunchGate: View {
    let message: String
    var body: some View {
        VStack(spacing: 22) {
            AgentOrb(mood: .working, tint: Palette.ice, size: 88)
            Text(message).font(Typo.callout).foregroundStyle(Palette.textSecondary)
        }
    }
}

struct SignInView: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var email = ""
    @State private var password = ""
    @State private var server = ""
    @State private var showServer = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 28) {
                Wordmark(size: 12)
                Spacer()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your AI team,\nnow on your Mac.")
                        .font(Typo.display(44))
                        .foregroundStyle(Palette.text)
                        .kerning(-1.2)
                        .lineSpacing(2)
                    Text("Command your employees, clear what needs you, and — when you allow it — let them work right here on this computer while you watch.")
                        .font(.system(size: 15))
                        .foregroundStyle(Palette.textSecondary)
                        .lineSpacing(4)
                        .frame(maxWidth: 440, alignment: .leading)
                }
                HStack(spacing: 18) {
                    feature("bolt.horizontal", "Instruct")
                    feature("checkmark.seal", "Approve")
                    feature("cursorarrow.motionlines", "Act on your Mac")
                }
                Spacer()
                Text("© 2026 \(Brand.company)").font(Typo.caption).foregroundStyle(Palette.textFaint)
            }
            .padding(56)
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(alignment: .leading, spacing: 16) {
                AgentOrb(mood: store.isSigningIn ? .working : .idle, tint: Palette.ice, size: 56)
                    .padding(.bottom, 6)
                Text("Sign in").font(Typo.title).foregroundStyle(Palette.text)
                Text("Use the same account as the web console and iPhone app.")
                    .font(Typo.callout).foregroundStyle(Palette.textSecondary)
                SyphTextField(title: "Email", text: $email, symbol: "at")
                SyphTextField(title: "Password", text: $password, secure: true, symbol: "lock")
                    .onSubmit(submit)
                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(Typo.caption).foregroundStyle(Palette.coral)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button(action: submit) {
                    HStack {
                        if store.isSigningIn { ProgressView().controlSize(.small).tint(Palette.onSignal) }
                        Text(store.isSigningIn ? "Signing in" : "Continue")
                        Image(systemName: "arrow.right")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(SignalButtonStyle())
                .disabled(email.isEmpty || password.isEmpty || store.isSigningIn)
                .keyboardShortcut(.defaultAction)

                DisclosureGroup(isExpanded: $showServer) {
                    HStack {
                        SyphTextField(title: APIClient.defaultServer, text: $server, symbol: "server.rack")
                        Button("Use") { store.api.server = server.isEmpty ? APIClient.defaultServer : server }
                            .buttonStyle(GhostButtonStyle(compact: true))
                    }
                    .padding(.top, 6)
                } label: {
                    Text("Server").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                }
                .tint(Palette.textTertiary)
            }
            .padding(32)
            .frame(width: 400)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Palette.panel.opacity(0.75))
                    .background(VisualEffect(material: .hudWindow).clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous)))
            )
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Palette.hairline, lineWidth: 0.75))
            .shadow(color: Palette.shadow.opacity(0.5), radius: 40, y: 20)
            .padding(56)
        }
        .onAppear { server = store.api.server == APIClient.defaultServer ? "" : store.api.server }
    }

    private func feature(_ symbol: String, _ title: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: symbol).foregroundStyle(Palette.ice)
            Text(title).foregroundStyle(Palette.textSecondary)
        }
        .font(Typo.callout)
    }

    private func submit() {
        guard !email.isEmpty, !password.isEmpty else { return }
        Task { await store.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password) }
    }
}

struct Shell: View {
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
                .frame(width: 232)
            Rectangle().fill(Palette.hairline).frame(width: 0.5)
            ZStack {
                switch app.section {
                case .chat: ChatScreen()
                case .team: TeamScreen()
                case .approvals: ApprovalsScreen()
                case .work: WorkScreen()
                case .library: LibraryScreen()
                case .computer: ComputerScreen()
                case .settings: SettingsScreen()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .id(app.section)
            .transition(.opacity)
        }
        .overlay(alignment: .bottom) { ToastLayer() }
        .sheet(isPresented: Binding(get: { app.showHire }, set: { app.showHire = $0 })) {
            HireSheet().environment(app).environment(store).appAppearance()
        }
    }
}

struct ToastLayer: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(spacing: 8) {
            if let error = store.errorMessage {
                toast(error, symbol: "exclamationmark.triangle.fill", tint: Palette.coral) { store.errorMessage = nil }
            }
            if let toast = store.toast {
                self.toast(toast, symbol: "checkmark.circle.fill", tint: Palette.mint) { store.toast = nil }
                    .task(id: toast) {
                        try? await Task.sleep(for: .seconds(3))
                        if store.toast == toast { store.toast = nil }
                    }
            }
        }
        .padding(.bottom, 20)
        .animation(Motion.snappy, value: store.errorMessage)
        .animation(Motion.snappy, value: store.toast)
    }

    private func toast(_ text: String, symbol: String, tint: Color, dismiss: @escaping () -> Void) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(Typo.callout).foregroundStyle(Palette.text).lineLimit(2)
            Button(action: dismiss) { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(Palette.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Capsule().fill(Palette.panelHigh.opacity(0.95)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.35), lineWidth: 0.75))
        .shadow(color: Palette.shadow.opacity(0.4), radius: 16, y: 6)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

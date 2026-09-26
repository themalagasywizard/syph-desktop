import SwiftUI
import AppKit

struct ComputerScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        let policy = app.policy
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                ControlHero()
                PermissionStrip()
                HStack(alignment: .top, spacing: 22) {
                    VStack(alignment: .leading, spacing: 26) {
                        ScopeGrid()
                        FolderList()
                    }
                    .frame(maxWidth: .infinity)
                    VStack(alignment: .leading, spacing: 26) {
                        WhoCanDrive()
                        ActionLog()
                        LinkedMacs()
                    }
                    .frame(width: 360)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 40)
            .padding(.bottom, 28)
        }
        .onAppear { policy.refreshSystemGrants() }
        .task {
            // System Settings changes don't notify us; poll while this screen is up.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                policy.refreshSystemGrants()
            }
        }
    }
}

private struct ControlHero: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let policy = app.policy
        let bridge = app.bridge
        let on = policy.controlEnabled
        HStack(spacing: 26) {
            ZStack {
                if on {
                    Circle()
                        .fill(RadialGradient(colors: [Palette.mint.opacity(0.18), .clear], center: .center, startRadius: 10, endRadius: 90))
                        .frame(width: 180, height: 180)
                }
                AgentOrb(mood: bridge.isRunning ? .working : (on ? .idle : .offline), tint: on ? Palette.mint : Palette.ice, size: 112)
            }
            .frame(width: 140, height: 140)
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "This Mac · \(Host.current().localizedName ?? "Mac")", color: on ? Palette.mint : Palette.textTertiary)
                    .lineLimit(1).truncationMode(.middle)
                Text(bridge.isRunning ? "\(bridge.current?.employee ?? "An employee") is working here"
                     : (on ? "Your team can work on this Mac" : "Computer control is off"))
                    .font(Typo.display(28)).foregroundStyle(Palette.text).kerning(-0.6)
                Text(on ? "They see only what the scopes below allow. Everything they do glows on screen and is logged. Press ⌃⌥⌘. anywhere to stop instantly."
                        : "Turn it on to let employees read your screen, open apps, click, type and work with shared files — always within the limits you set.")
                    .font(Typo.body).foregroundStyle(Palette.textSecondary).lineSpacing(3)
                    .frame(maxWidth: 560, alignment: .leading)
                HStack(spacing: 10) {
                    if on {
                        Button { app.bridge.emergencyStop() } label: { Label("Turn off", systemImage: "power") }
                            .buttonStyle(GhostButtonStyle(tint: Palette.coral))
                    } else {
                        Button { policy.controlEnabled = true } label: { Label("Allow computer control", systemImage: "power") }
                            .buttonStyle(SignalButtonStyle())
                    }
                    HStack(spacing: 4) { KeyCap(key: "⌃"); KeyCap(key: "⌥"); KeyCap(key: "⌘"); KeyCap(key: ".") }
                    Text("kill switch").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                    Spacer()
                    linkBadge(bridge.link)
                }
                .padding(.top, 4)
            }
        }
        .padding(26)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [(on ? Palette.mint : Palette.ice).opacity(0.07), Color.white.opacity(0.015)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(LinearGradient(colors: [(on ? Palette.mint : Palette.ice).opacity(0.35), Palette.hairline],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.9)
        )
        .animation(Motion.soft, value: on)
    }

    private func linkBadge(_ link: DeviceBridge.Link) -> some View {
        let (text, color): (String, Color) = {
            switch link {
            case .online: return ("Linked", Palette.mint)
            case .linking: return ("Linking", Palette.amber)
            case .idle: return ("Not linked", Palette.textTertiary)
            case .offline: return ("Reconnecting", Palette.coral)
            }
        }()
        return HStack(spacing: 4) {
            StatusDot(color: color, pulsing: link == .linking, size: 6)
            Text(text).font(Typo.caption).foregroundStyle(color)
        }
    }
}

private struct PermissionStrip: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        HStack(spacing: 12) {
            ForEach(SystemPermission.allCases) { permission in
                let granted = app.policy.systemGrants[permission] ?? false
                HStack(spacing: 12) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .font(.system(size: 18))
                        .foregroundStyle(granted ? Palette.mint : Palette.amber)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(permission.title).font(Typo.headline).foregroundStyle(Palette.text)
                        Text(permission.detail).font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(2)
                    }
                    Spacer(minLength: 4)
                    if !granted {
                        Button("Grant") { permission.request() }.buttonStyle(GhostButtonStyle(tint: Palette.amber, compact: true))
                    } else if permission == .automation {
                        Button("Review") { permission.request() }.buttonStyle(GhostButtonStyle(compact: true))
                    }
                }
                .card(radius: 14, padding: 14)
            }
        }
    }
}

private struct ScopeGrid: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Eyebrow(text: "What they may do")
                Spacer()
                Button("Safe defaults") {
                    for scope in ComputerScope.allCases { app.policy.set(scope, scope.defaultMode) }
                }
                .buttonStyle(GhostButtonStyle(compact: true))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                ForEach(ComputerScope.allCases) { scope in
                    ScopeCard(scope: scope)
                }
            }
        }
        .opacity(app.policy.controlEnabled ? 1 : 0.55)
    }
}

private struct ScopeCard: View {
    let scope: ComputerScope
    @Environment(AppModel.self) private var app

    var body: some View {
        let mode = app.policy.mode(scope)
        let needs = scope.systemRequirement
        let blocked = needs.map { !(app.policy.systemGrants[$0] ?? false) } ?? false
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8).fill(color(mode).opacity(0.12))
                    Image(systemName: scope.symbol).font(.system(size: 13)).foregroundStyle(color(mode))
                }
                .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(scope.title).font(Typo.headline).foregroundStyle(Palette.text)
                    HStack(spacing: 2) {
                        ForEach(0..<4) { level in
                            Capsule().fill(level < scope.risk + 1 ? riskColor : Palette.textFaint).frame(width: 9, height: 3)
                        }
                        Text(riskLabel).font(.system(size: 9.5, weight: .medium)).foregroundStyle(Palette.textTertiary).padding(.leading, 4)
                    }
                }
                Spacer()
            }
            Text(scope.detail).font(Typo.caption).foregroundStyle(Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            if blocked, let needs {
                Button { needs.request() } label: {
                    Label("Needs \(needs.title) permission", systemImage: "exclamationmark.triangle")
                        .font(Typo.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.amber)
            }
            Picker("", selection: Binding(get: { mode }, set: { app.policy.set(scope, $0) })) {
                ForEach(ScopeMode.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .card(radius: 14, padding: 14, highlighted: mode == .allow)
    }

    private func color(_ mode: ScopeMode) -> Color {
        switch mode {
        case .off: return Palette.textTertiary
        case .ask: return Palette.amber
        case .allow: return Palette.mint
        }
    }

    private var riskColor: Color {
        switch scope.risk {
        case 0, 1: return Palette.mint
        case 2: return Palette.amber
        default: return Palette.coral
        }
    }

    private var riskLabel: String {
        ["Low", "Low", "Medium", "High"][min(scope.risk, 3)]
    }
}

private struct FolderList: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "Shared folders")
                Spacer()
                Button { addFolder() } label: { Label("Share a folder", systemImage: "plus") }
                    .buttonStyle(GhostButtonStyle(compact: true))
            }
            Text("File scopes only ever reach inside these folders. Commands run from the first one.")
                .font(Typo.caption).foregroundStyle(Palette.textTertiary)
            ForEach(app.policy.sharedFolders, id: \.path) { folder in
                HStack(spacing: 10) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path))
                        .resizable().frame(width: 22, height: 22)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(folder.lastPathComponent).font(Typo.callout).foregroundStyle(Palette.text)
                        Text(folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                            .font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1).truncationMode(.middle)
                    }
                    Spacer()
                    IconButton(symbol: "arrow.up.forward.app", help: "Show in Finder", size: 22) {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                    IconButton(symbol: "minus.circle", help: "Stop sharing", size: 22) { app.policy.removeFolder(folder) }
                }
                .card(radius: 10, padding: 10)
            }
        }
    }

    private func addFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Share"
        panel.message = "Choose folders your employees may work in."
        if panel.runModal() == .OK {
            panel.urls.forEach { app.policy.addFolder($0) }
        }
    }
}

private struct WhoCanDrive: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Who can use this Mac")
            ForEach(store.employees) { employee in
                let on = employee.toolIds.contains("computer")
                HStack(spacing: 10) {
                    Monogram(employee: employee, size: 26)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(employee.name).font(Typo.callout).foregroundStyle(Palette.text)
                        Text(employee.autonomyLevel == "conservative" ? "Asks before every action" : "Acts within your scopes")
                            .font(Typo.caption).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    Toggle("", isOn: Binding(get: { on }, set: { value in
                        Task { await store.setTool("computer", enabled: value, for: employee) }
                    }))
                    .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                }
            }
            if store.employees.isEmpty {
                Text("Hire an employee first.").font(Typo.caption).foregroundStyle(Palette.textTertiary)
            }
        }
        .card(radius: 16, padding: 16)
    }
}

private struct ActionLog: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let bridge = app.bridge
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Eyebrow(text: "Live on this Mac")
                Spacer()
                if bridge.isRunning { StatusDot(color: Palette.ice, pulsing: true, size: 6) }
            }
            if let current = bridge.current {
                row(current, live: true)
            }
            ForEach(bridge.log.prefix(14)) { action in row(action, live: false) }
            if bridge.log.isEmpty && bridge.current == nil {
                Text("Nothing yet. Try asking an employee: “Read my screen and tell me what’s open.”")
                    .font(Typo.caption).foregroundStyle(Palette.textTertiary)
            }
        }
        .card(radius: 16, padding: 16)
    }

    private func row(_ action: LocalAction, live: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: action.scope?.symbol ?? "circle")
                .font(.system(size: 11))
                .foregroundStyle(Palette.status(action.status))
                .frame(width: 22, height: 22)
                .background(Circle().fill(Palette.status(action.status).opacity(0.12)))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(action.employee.isEmpty ? "Employee" : action.employee).font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(action.operation.replacingOccurrences(of: "_", with: " ")).font(Typo.caption).foregroundStyle(Palette.textTertiary)
                    Spacer()
                    Text(live ? "now" : action.startedAt.formatted(date: .omitted, time: .shortened))
                        .font(Typo.caption).foregroundStyle(Palette.textFaint)
                }
                Text(action.summary).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(2)
                if let thumb = action.thumbnail {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Palette.hairline, lineWidth: 0.5))
                        .frame(maxHeight: 110)
                }
            }
        }
    }
}

private struct LinkedMacs: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let bridge = app.bridge
        VStack(alignment: .leading, spacing: 10) {
            Eyebrow(text: "Linked computers")
            ForEach(bridge.remoteDevices) { device in
                HStack(spacing: 10) {
                    Image(systemName: "laptopcomputer").foregroundStyle(device.online ? Palette.mint : Palette.textTertiary)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(device.name + (device.id == bridge.deviceID ? " (this Mac)" : ""))
                            .font(Typo.callout).foregroundStyle(Palette.text)
                        Text("\(device.model) · macOS \(device.osVersion) · \(device.online ? "online" : "offline")")
                            .font(Typo.caption).foregroundStyle(Palette.textTertiary)
                    }
                    Spacer()
                    if device.id != bridge.deviceID {
                        IconButton(symbol: "link.badge.plus", help: "Unlink", size: 22) { Task { await bridge.unlink(device) } }
                    }
                }
            }
        }
        .card(radius: 16, padding: 16)
        .task { await bridge.refreshDevices() }
    }
}

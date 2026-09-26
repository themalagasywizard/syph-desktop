import SwiftUI

struct Sidebar: View {
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Wordmark(size: 11)
                Spacer()
            }
            .padding(.leading, 18)
            .padding(.top, 38)
            .padding(.bottom, 18)

            Button { app.toggleCommandBar() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkle").foregroundStyle(Palette.ice)
                    Text("Ask your team…").foregroundStyle(Palette.textTertiary).lineLimit(1).fixedSize()
                    Spacer()
                    KeyCap(key: "⌥␣")
                }
                .font(Typo.callout)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 9).fill(Palette.field))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Palette.hairline, lineWidth: 0.75))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.bottom, 14)

            VStack(spacing: 2) {
                ForEach(AppSection.allCases.filter { $0 != .settings }) { section in
                    SidebarRow(section: section, badge: badge(for: section), selected: app.section == section) {
                        app.go(section)
                    }
                }
            }
            .padding(.horizontal, 8)

            Eyebrow(text: "Team").padding(.leading, 20).padding(.top, 22).padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 2) {
                    ForEach(store.employees) { employee in
                        EmployeeRailRow(employee: employee)
                    }
                    Button { app.showHire = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "plus")
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 24, height: 24)
                                .overlay(Circle().strokeBorder(Palette.hairlineStrong, style: StrokeStyle(lineWidth: 0.75, dash: [2, 2])))
                            Text("Hire")
                            Spacer()
                        }
                        .font(Typo.callout)
                        .foregroundStyle(Palette.textTertiary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 8)
            }

            Spacer(minLength: 0)
            ComputerStatusTile()
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            HStack(spacing: 10) {
                if let user = store.user {
                    Text(String(user.name.prefix(1)).uppercased())
                        .font(.system(size: 11, weight: .semibold))
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(user.name).font(Typo.callout).foregroundStyle(Palette.text).lineLimit(1)
                        Text(user.email).font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                    }
                }
                Spacer()
                IconButton(symbol: "slider.horizontal.3", help: "Settings") { app.go(.settings) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 0.5) }
        }
        .background(VisualEffect(material: .sidebar).opacity(0.55))
        .background(Palette.void.opacity(0.6))
    }

    private func badge(for section: AppSection) -> Int {
        switch section {
        case .approvals: return store.waitingApprovals.count
        case .chat: return store.activeEmployeeCount
        default: return 0
        }
    }
}

private struct SidebarRow: View {
    let section: AppSection
    let badge: Int
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                    .foregroundStyle(selected ? Palette.ice : Palette.textSecondary)
                Text(section.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Palette.text : Palette.textSecondary)
                Spacer()
                if badge > 0 {
                    Text("\(badge)")
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundStyle(section == .approvals ? Palette.void : Palette.mint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(section == .approvals ? Palette.amber : Palette.mint.opacity(0.15)))
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? Color.white.opacity(0.07) : (hovering ? Color.white.opacity(0.035) : .clear))
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule().fill(Palette.ice).frame(width: 2.5, height: 14).offset(x: -4)
                        .shadow(color: Palette.ice, radius: 4)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: selected)
    }
}

private struct EmployeeRailRow: View {
    let employee: Employee
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store
    @State private var hovering = false

    var body: some View {
        let waiting = store.waitingApprovals.contains { $0.employeeId == employee.id }
        let mood = AgentOrb.Mood(employee: employee, working: store.working[employee.id], waiting: waiting)
        Button {
            store.select(employee)
            app.go(.chat)
        } label: {
            HStack(spacing: 10) {
                AgentOrb(mood: mood, tint: Palette.hue(for: employee.id), size: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(employee.name).font(Typo.callout).foregroundStyle(Palette.text).lineLimit(1)
                    Text(subtitle(mood)).font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(store.selectedEmployee?.id == employee.id && app.section == .chat ? Color.white.opacity(0.06)
                          : (hovering ? Color.white.opacity(0.03) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private func subtitle(_ mood: AgentOrb.Mood) -> String {
        switch mood {
        case .working: return store.working[employee.id]?.phase.capitalized ?? "Working"
        case .attention: return "Needs you"
        case .paused: return "Paused"
        default: return employee.role.isEmpty ? "Idle" : employee.role
        }
    }
}

/// Sidebar tile that shows whether employees can reach this Mac.
struct ComputerStatusTile: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        let bridge = app.bridge
        let enabled = app.policy.controlEnabled
        Button { app.go(.computer) } label: {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7).fill((enabled ? Palette.mint : Palette.textTertiary).opacity(0.12))
                    Image(systemName: bridge.isRunning ? "cursorarrow.motionlines" : "desktopcomputer")
                        .font(.system(size: 12))
                        .foregroundStyle(enabled ? Palette.mint : Palette.textTertiary)
                }
                .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(bridge.isRunning ? "Working on this Mac" : (enabled ? "Mac control on" : "Mac control off"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Palette.text)
                    Text(linkText(bridge.link)).font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                }
                Spacer()
                StatusDot(color: bridge.link == .online ? (enabled ? Palette.mint : Palette.amber) : Palette.coral,
                          pulsing: bridge.isRunning, size: 6)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 11).fill(Color.white.opacity(0.03)))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Palette.hairline, lineWidth: 0.75))
        }
        .buttonStyle(.plain)
    }

    private func linkText(_ link: DeviceBridge.Link) -> String {
        switch link {
        case .idle: return "Not linked"
        case .linking: return "Linking…"
        case .online: return "Linked to your workspace"
        case .offline: return "Reconnecting…"
        }
    }
}

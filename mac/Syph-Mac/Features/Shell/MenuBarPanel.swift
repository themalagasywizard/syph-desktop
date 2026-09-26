import SwiftUI
import AppKit

/// The menu bar companion: who is working, what needs you, and the Mac switch.
struct MenuBarPanel: View {
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Wordmark(size: 10)
                Spacer()
                Button { open(.chat) } label: { Text("Open").font(Typo.caption) }
                    .buttonStyle(GhostButtonStyle(compact: true))
            }
            if store.phase != .ready {
                Text("Sign in to see your team.").font(Typo.callout).foregroundStyle(Palette.textSecondary)
            } else {
                if !store.waitingApprovals.isEmpty {
                    Eyebrow(text: "Needs you", color: Palette.amber)
                    ForEach(store.waitingApprovals.prefix(3)) { approval in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(approval.title).font(Typo.callout).foregroundStyle(Palette.text).lineLimit(1)
                                Text(store.employee(approval.employeeId)?.name ?? "").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                            }
                            Spacer()
                            IconButton(symbol: "xmark", help: "Decline", tint: Palette.coral, size: 22) {
                                Task { await store.resolve(approval, approve: false) }
                            }
                            IconButton(symbol: "checkmark", help: "Approve", tint: Palette.mint, size: 22) {
                                Task { await store.resolve(approval, approve: true) }
                            }
                        }
                    }
                }
                Eyebrow(text: "Team")
                ForEach(store.employees.prefix(6)) { employee in
                    let run = store.working[employee.id]
                    let waiting = store.waitingApprovals.contains { $0.employeeId == employee.id }
                    Button {
                        store.select(employee)
                        open(.chat)
                    } label: {
                        HStack(spacing: 10) {
                            AgentOrb(mood: .init(employee: employee, working: run, waiting: waiting),
                                     tint: Palette.hue(for: employee.id), size: 22)
                            Text(employee.name).font(Typo.callout).foregroundStyle(Palette.text)
                            Spacer()
                            Text(run?.active == true ? "Working" : (employee.isPaused ? "Paused" : "Ready"))
                                .font(Typo.caption).foregroundStyle(Palette.textTertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                Rectangle().fill(Palette.hairline).frame(height: 0.5)
                Toggle(isOn: Binding(get: { app.policy.controlEnabled },
                                     set: { value in if value { app.policy.controlEnabled = true } else { app.bridge.emergencyStop() } })) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Computer control").font(Typo.callout).foregroundStyle(Palette.text)
                        Text(app.bridge.isRunning ? "\(app.bridge.current?.employee ?? "An employee") is working here" : "⌃⌥⌘. stops it anywhere")
                            .font(Typo.caption).foregroundStyle(Palette.textTertiary)
                    }
                }
                .toggleStyle(.switch)
                .controlSize(.small)
                HStack {
                    Button("Command bar  ⌥Space") { app.toggleCommandBar() }
                        .buttonStyle(.plain).font(Typo.caption).foregroundStyle(Palette.textSecondary)
                    Spacer()
                    Button("Quit") { NSApp.terminate(nil) }
                        .buttonStyle(.plain).font(Typo.caption).foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .padding(16)
        .frame(width: 320)
        .background(Palette.void.opacity(0.4))
    }

    private func open(_ section: AppSection) {
        openWindow(id: "main")
        app.go(section)
    }
}

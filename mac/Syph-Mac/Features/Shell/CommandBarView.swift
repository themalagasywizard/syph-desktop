import SwiftUI
import AppKit

/// ⌥Space from anywhere: tell an employee what to do without leaving your app.
/// Tab cycles the employee, ↩ sends, ⌘↩ sends and opens the conversation,
/// Esc closes. Typing a section name offers to jump there.
struct CommandBarView: View {
    let close: () -> Void
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store
    @State private var text = ""
    @State private var targetID: String?
    @State private var sent: String?
    @FocusState private var focused: Bool

    private var target: Employee? { store.employee(targetID) ?? store.selectedEmployee }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                AgentOrb(mood: store.isSending ? .working : (sent != nil ? .idle : .idle),
                         tint: target.map { Palette.hue(for: $0.id) } ?? Palette.ice, size: 34)
                TextField(target.map { "Tell \($0.name) what to do…" } ?? "Ask your team…", text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(Palette.text)
                    .focused($focused)
                    .onSubmit { submit(openAfter: false) }
                if let target {
                    Button { cycle() } label: {
                        HStack(spacing: 6) {
                            Monogram(employee: target, size: 20)
                            Text(target.name).font(Typo.callout).foregroundStyle(Palette.text)
                            KeyCap(key: "⇥")
                        }
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(Capsule().fill(Palette.overlay.opacity(0.06)))
                    }
                    .buttonStyle(.plain)
                    .help("Tab to switch employee")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)

            Rectangle().fill(Palette.hairline).frame(height: 0.5)

            VStack(alignment: .leading, spacing: 2) {
                if let sent {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.mint)
                        Text(sent).font(Typo.callout).foregroundStyle(Palette.text)
                    }
                    .padding(12)
                } else {
                    ForEach(actions) { action in
                        CommandRow(action: action) { run(action) }
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
            HStack(spacing: 14) {
                hint("↩", "send"); hint("⌘↩", "send & open"); hint("⇥", "switch employee"); hint("esc", "close")
                Spacer()
                if !store.waitingApprovals.isEmpty {
                    Text("\(store.waitingApprovals.count) waiting on you").font(Typo.caption).foregroundStyle(Palette.amber)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Palette.inset)
        }
        .frame(width: 680, height: 420)
        .background(
            ZStack {
                VisualEffect(material: .hudWindow)
                Palette.void.opacity(0.62)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(LinearGradient(colors: [Palette.ice.opacity(0.45), Palette.hairline, Palette.hairline],
                                             startPoint: .top, endPoint: .bottom), lineWidth: 1)
        )
        .onKeyPress(.tab) { cycle(); return .handled }
        .onKeyPress(.escape) { close(); return .handled }
        .onKeyPress(.return, phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            submit(openAfter: true)
            return .handled
        }
        .onReceive(NotificationCenter.default.publisher(for: .commandBarOpened)) { _ in
            sent = nil
            text = ""
            targetID = store.selectedEmployee?.id
            focused = true
        }
        .onAppear { focused = true; targetID = store.selectedEmployee?.id }
    }

    // MARK: Actions

    struct BarAction: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String
        let perform: () -> Void
    }

    private var actions: [BarAction] {
        let query = text.lowercased().trimmingCharacters(in: .whitespaces)
        var list: [BarAction] = []
        if let target, !query.isEmpty {
            list.append(BarAction(id: "send", symbol: "paperplane", title: "Send to \(target.name)", detail: text) { submit(openAfter: false) })
        }
        let jumps: [BarAction] = AppSection.allCases.map { section in
            BarAction(id: "go-\(section.rawValue)", symbol: section.symbol, title: "Go to \(section.title)", detail: "") {
                app.go(section); close()
            }
        }
        let extras: [BarAction] = [
            BarAction(id: "hire", symbol: "person.badge.plus", title: "Hire an employee", detail: "") {
                app.go(.team); app.showHire = true; close()
            },
            BarAction(id: "pause", symbol: "pause.circle", title: "Pause all employees", detail: "") {
                Task { await store.pauseAll() }; close()
            },
            BarAction(id: "stop", symbol: "hand.raised", title: app.policy.controlEnabled ? "Stop computer control" : "Allow computer control", detail: "") {
                if app.policy.controlEnabled { app.bridge.emergencyStop() } else { app.policy.controlEnabled = true }
                close()
            },
        ]
        let people: [BarAction] = store.employees.map { employee in
            BarAction(id: "emp-\(employee.id)", symbol: "person", title: "Talk to \(employee.name)", detail: employee.role) {
                targetID = employee.id
            }
        }
        let pool = jumps + extras + people
        if query.isEmpty {
            return Array((store.waitingApprovals.isEmpty ? [] : [pool[2]]) + extras + Array(people.prefix(3)))
        }
        let matches = pool.filter { $0.title.lowercased().contains(query) || $0.detail.lowercased().contains(query) }
        return list + Array(matches.prefix(5))
    }

    private func run(_ action: BarAction) { action.perform() }

    private func cycle() {
        guard !store.employees.isEmpty else { return }
        let index = store.employees.firstIndex { $0.id == target?.id } ?? -1
        targetID = store.employees[(index + 1) % store.employees.count].id
    }

    private func submit(openAfter: Bool) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let target, !body.isEmpty else { return }
        text = ""
        Task {
            if await store.send(body, to: target.id) {
                withAnimation(Motion.snappy) { sent = "Sent to \(target.name). They’re on it." }
                if openAfter {
                    store.select(target)
                    app.go(.chat)
                    close()
                } else {
                    try? await Task.sleep(for: .milliseconds(1100))
                    close()
                }
            } else {
                text = body
            }
        }
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            KeyCap(key: key)
            Text(label).font(Typo.caption).foregroundStyle(Palette.textTertiary)
        }
    }
}

private struct CommandRow: View {
    let action: CommandBarView.BarAction
    let perform: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: perform) {
            HStack(spacing: 12) {
                Image(systemName: action.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Palette.ice)
                    .frame(width: 28, height: 28)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Palette.ice.opacity(0.1)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(action.title).font(Typo.callout).foregroundStyle(Palette.text)
                    if !action.detail.isEmpty {
                        Text(action.detail).font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Palette.overlay.opacity(0.06) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

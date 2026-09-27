import SwiftUI

struct ApprovalsScreen: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var selectedID: String?
    @State private var showDecided = false

    var body: some View {
        let waiting = store.waitingApprovals
        let decided = store.approvals.filter { $0.status != "waiting" }.prefix(30)
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(eyebrow: "Needs you", title: waiting.isEmpty ? "All clear" : "\(waiting.count) decision\(waiting.count == 1 ? "" : "s") waiting",
                             detail: "Anything that sends, spends, deletes or acts on your Mac waits here until you say so.")
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(waiting) { approval in
                            ApprovalListRow(approval: approval, selected: current(waiting)?.id == approval.id)
                                .onTapGesture { selectedID = approval.id }
                        }
                        if waiting.isEmpty {
                            EmptyState(symbol: "checkmark.seal", title: "Nothing needs you",
                                       detail: "Your team is working within the limits you set.")
                                .frame(height: 260)
                        }
                        DisclosureGroup(isExpanded: $showDecided) {
                            VStack(spacing: 6) {
                                ForEach(Array(decided)) { approval in
                                    ApprovalListRow(approval: approval, selected: false).opacity(0.7)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Eyebrow(text: "Recently decided")
                        }
                        .padding(.top, 18)
                        .tint(Palette.textTertiary)
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
            }
            .frame(width: 380)
            Rectangle().fill(Palette.hairline).frame(width: 0.5)
            Group {
                if let approval = current(waiting) {
                    ScrollView {
                        ApprovalCard(approval: approval, compact: false)
                            .padding(32)
                            .frame(maxWidth: 720)
                            .frame(maxWidth: .infinity)
                    }
                    .id(approval.id)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                } else {
                    EmptyState(symbol: "sparkles", title: "Inbox zero", detail: "New requests appear here and as notifications.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .animation(Motion.snappy, value: selectedID)
    }

    private func current(_ waiting: [Approval]) -> Approval? {
        waiting.first { $0.id == selectedID } ?? waiting.first
    }
}

private struct ApprovalListRow: View {
    let approval: Approval
    let selected: Bool
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let employee = store.employee(approval.employeeId) {
                Monogram(employee: employee, size: 30)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(approval.title).font(Typo.headline).foregroundStyle(Palette.text).lineLimit(2)
                Text(approval.situation).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(2)
                HStack(spacing: 6) {
                    Text(store.employee(approval.employeeId)?.name ?? "").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                    if approval.status != "waiting" { Chip(text: approval.status.capitalized, color: Palette.status(approval.status)) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? Palette.overlay.opacity(0.07) : Palette.overlay.opacity(0.02)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Palette.amber.opacity(0.5) : Palette.hairline, lineWidth: 0.75))
        .contentShape(Rectangle())
    }
}

/// A decision, with the context needed to make it and nothing else.
struct ApprovalCard: View {
    let approval: Approval
    var compact: Bool
    @Environment(WorkspaceStore.self) private var store
    @State private var busy = false

    var body: some View {
        let employee = store.employee(approval.employeeId)
        VStack(alignment: .leading, spacing: compact ? 12 : 20) {
            HStack(spacing: 12) {
                AgentOrb(mood: .attention, tint: Palette.amber, size: compact ? 28 : 40)
                VStack(alignment: .leading, spacing: 2) {
                    Eyebrow(text: "\(employee?.name ?? "Employee") needs your decision", color: Palette.amber)
                    Text(approval.title).font(compact ? Typo.headline : Typo.display(22)).foregroundStyle(Palette.text)
                }
            }
            if !approval.situation.isEmpty { block("What happens", approval.situation, symbol: "arrow.forward.circle") }
            if !compact {
                if !approval.recommendation.isEmpty && approval.recommendation != approval.reason {
                    block("Recommendation", approval.recommendation, symbol: "lightbulb")
                }
                if !approval.risk.isEmpty { block("Risk", approval.risk, symbol: "exclamationmark.shield") }
            }
            HStack(spacing: 10) {
                Button("Decline") { decide(false) }
                    .buttonStyle(GhostButtonStyle(tint: Palette.coral))
                    .keyboardShortcut(compact ? nil : KeyboardShortcut(.delete, modifiers: [.command]))
                Spacer()
                if busy { ProgressView().controlSize(.small) }
                Button {
                    decide(true)
                } label: {
                    Label(approval.primaryAction.isEmpty ? "Approve" : approval.primaryAction, systemImage: "checkmark")
                }
                .buttonStyle(SignalButtonStyle())
                .keyboardShortcut(compact ? nil : KeyboardShortcut(.return, modifiers: [.command]))
            }
            if !compact {
                HStack(spacing: 6) {
                    KeyCap(key: "⌘↩"); Text("approve").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                    KeyCap(key: "⌘⌫").padding(.leading, 8); Text("decline").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                }
            }
        }
        .disabled(busy)
        .card(radius: 16, padding: compact ? 14 : 22, highlighted: true)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Palette.amber.opacity(0.3), lineWidth: 0.75)
        )
    }

    private func block(_ title: String, _ text: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(Typo.caption).foregroundStyle(Palette.textTertiary)
            Text(text).font(Typo.body).foregroundStyle(Palette.text.opacity(0.9)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func decide(_ approve: Bool) {
        busy = true
        Task {
            await store.resolve(approval, approve: approve)
            busy = false
        }
    }
}

/// Large page header used by every screen.
struct ScreenHeader<Trailing: View>: View {
    let eyebrow: String
    let title: String
    var detail: String = ""
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 6) {
                Eyebrow(text: eyebrow, color: Palette.ice)
                Text(title).font(Typo.display(26)).foregroundStyle(Palette.text).kerning(-0.5)
                if !detail.isEmpty {
                    Text(detail).font(Typo.callout).foregroundStyle(Palette.textSecondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer()
            trailing()
        }
        .padding(.horizontal, 24)
        .padding(.top, 40)
        .padding(.bottom, 20)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(eyebrow: String, title: String, detail: String = "") {
        self.init(eyebrow: eyebrow, title: title, detail: detail, trailing: { EmptyView() })
    }
}

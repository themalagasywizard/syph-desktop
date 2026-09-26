import SwiftUI
import AppKit

struct ChatScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store
    @State private var showThreads = true

    var body: some View {
        if let employee = store.selectedEmployee {
            HStack(spacing: 0) {
                VStack(spacing: 0) {
                    ChatHeader(employee: employee, showThreads: $showThreads)
                    MessageStream(employee: employee)
                    Composer(employee: employee)
                }
                if showThreads {
                    Rectangle().fill(Palette.hairline).frame(width: 0.5)
                    ThreadInspector(employee: employee)
                        .frame(width: 272)
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .animation(Motion.snappy, value: showThreads)
        } else {
            VStack(spacing: 18) {
                EmptyState(symbol: "person.badge.plus", title: "Hire your first employee",
                           detail: "Give them a mission, the tools they need and the limits you want. They start working right away.")
                    .frame(maxHeight: 260)
                Button("Hire an employee") { app.showHire = true }.buttonStyle(SignalButtonStyle())
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

private struct ChatHeader: View {
    let employee: Employee
    @Binding var showThreads: Bool
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        let run = store.working[employee.id]
        let waiting = store.waitingApprovals.contains { $0.employeeId == employee.id }
        HStack(spacing: 14) {
            AgentOrb(mood: .init(employee: employee, working: run, waiting: waiting),
                     tint: Palette.hue(for: employee.id), size: 42)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(employee.name).font(.system(size: 17, weight: .semibold)).foregroundStyle(Palette.text)
                    Chip(text: statusText(run), color: statusColor(run, waiting: waiting))
                }
                Text(employee.missionTitle.isEmpty ? employee.role : employee.missionTitle)
                    .font(Typo.callout).foregroundStyle(Palette.textSecondary).lineLimit(1)
            }
            Spacer()
            employeeSwitcher
            IconButton(symbol: "sun.max", help: "Wake up now") { Task { await store.wake(employee.id) } }
            IconButton(symbol: employee.isPaused ? "play.fill" : "pause", help: employee.isPaused ? "Resume" : "Pause") {
                Task {
                    if employee.isPaused { await store.resume(employee.id) } else { await store.pause(employee.id) }
                }
            }
            IconButton(symbol: "square.and.pencil", help: "New conversation") {
                Task { await store.newThread(for: employee.id) }
            }
            IconButton(symbol: "sidebar.right", help: "Threads & activity", tint: showThreads ? Palette.ice : Palette.textSecondary) {
                showThreads.toggle()
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 30)
        .padding(.bottom, 14)
        .hairlineBottom()
    }

    private var employeeSwitcher: some View {
        Menu {
            ForEach(store.employees) { other in
                Button(other.name) { store.select(other) }
            }
            Divider()
            Button("Hire…") { app.showHire = true }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.2")
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
            }
            .foregroundStyle(Palette.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Switch employee")
    }

    private func statusText(_ run: WorkingRun?) -> String {
        if employee.isPaused { return "Paused" }
        if run?.active == true { return run?.phase.isEmpty == false ? run!.phase.capitalized : "Working" }
        return "Ready"
    }

    private func statusColor(_ run: WorkingRun?, waiting: Bool) -> Color {
        if employee.isPaused { return Palette.textTertiary }
        if waiting { return Palette.amber }
        if run?.active == true { return Palette.ice }
        return Palette.mint
    }
}

private struct MessageStream: View {
    let employee: Employee
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        let messages = store.messages(for: employee.id)
        let approvals = store.waitingApprovals.filter { $0.employeeId == employee.id }
        let run = store.working[employee.id]
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    if messages.isEmpty {
                        Greeting(employee: employee)
                            .padding(.top, 60)
                    }
                    ForEach(messages) { message in
                        MessageRow(message: message, employee: employee)
                            .id(message.id)
                    }
                    if let run, run.active {
                        WorkingCard(run: run, employee: employee)
                            .id("working")
                    }
                    ForEach(approvals) { approval in
                        ApprovalCard(approval: approval, compact: true)
                    }
                    Color.clear.frame(height: 8).id("bottom")
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 22)
                .frame(maxWidth: 860)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.automatic)
            .onAppear { proxy.scrollTo("bottom", anchor: .bottom) }
            .onChange(of: messages.count) { _, _ in
                withAnimation(Motion.soft) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
            .onChange(of: run?.steps.count ?? 0) { _, _ in
                withAnimation(Motion.soft) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

private struct Greeting: View {
    let employee: Employee
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("What should \(employee.name) do next?")
                .font(Typo.display(26)).foregroundStyle(Palette.text).kerning(-0.5)
            Text(employee.mission).font(Typo.body).foregroundStyle(Palette.textSecondary).lineLimit(3)
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { text in
                    Button(text) {
                        store.drafts[employee.id] = text
                    }
                    .buttonStyle(GhostButtonStyle(compact: true))
                }
            }
        }
    }

    private var suggestions: [String] {
        var base = ["Brief me on today", "What needs my decision?"]
        if employee.toolIds.contains("computer") { base.append("Look at my screen and tidy my Desktop") }
        else { base.append("Research our top 3 competitors") }
        return base
    }
}

struct MessageRow: View {
    let message: ChatMessage
    let employee: Employee
    @State private var hovering = false

    var body: some View {
        if message.isUser {
            HStack {
                Spacer(minLength: 120)
                Text(message.body)
                    .font(Typo.body)
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(LinearGradient(colors: [Palette.iceDeep.opacity(0.45), Palette.iceDeep.opacity(0.25)],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                    )
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Palette.ice.opacity(0.25), lineWidth: 0.75))
                    .opacity(message.id.hasPrefix("local-") ? 0.6 : 1)
            }
        } else {
            let parsed = MessageParser.parse(message.body)
            HStack(alignment: .top, spacing: 12) {
                Monogram(employee: employee, size: 26)
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(employee.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.text)
                        Text(TimeText.clock(message.at)).font(Typo.caption).foregroundStyle(Palette.textTertiary)
                        Spacer()
                        if hovering {
                            IconButton(symbol: "doc.on.doc", help: "Copy", size: 22) {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(parsed.prose, forType: .string)
                            }
                        }
                    }
                    if !parsed.prose.isEmpty { MarkdownText(source: parsed.prose) }
                    ForEach(parsed.files) { FileCardView(card: $0) }
                    if let mail = parsed.mail { MailCardView(mail: mail) }
                    if let crm = parsed.crmTitle { Chip(text: crm, color: Palette.mint, symbol: "person.crop.rectangle.stack") }
                }
            }
            .onHover { hovering = $0 }
        }
    }
}

/// Live view of a run: goal, phase, and each tool step as it lands.
struct WorkingCard: View {
    let run: WorkingRun
    let employee: Employee
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AgentOrb(mood: .working, tint: Palette.hue(for: employee.id), size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(run.phase.isEmpty ? "Working" : run.phase.capitalized)
                        .font(.system(size: 12.5, weight: .semibold)).foregroundStyle(Palette.text)
                    Text(run.goal).font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                }
                Spacer()
                Button("Stop") { Task { await store.stop(employee.id) } }
                    .buttonStyle(GhostButtonStyle(tint: Palette.coral, compact: true))
            }
            if !run.steps.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(run.steps.enumerated()), id: \.offset) { index, step in
                        StepRow(step: step, last: index == run.steps.count - 1)
                    }
                }
            }
        }
        .card(radius: 14, padding: 14, highlighted: true)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }
}

private struct StepRow: View {
    let step: WorkingStep
    let last: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                StatusDot(color: Palette.status(step.status), pulsing: step.status == "running" || step.status == "executing", size: 6)
                if !last { Rectangle().fill(Palette.hairlineStrong).frame(width: 0.75).frame(maxHeight: .infinity) }
            }
            .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: symbol).font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                    Text(step.label.isEmpty ? "\(step.tool) · \(step.operation)" : step.label)
                        .font(Typo.callout).foregroundStyle(Palette.text)
                }
                if !step.summary.isEmpty {
                    Text(step.summary).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(3)
                }
            }
            .padding(.bottom, 10)
        }
    }

    private var symbol: String {
        switch step.tool {
        case "computer": return "desktopcomputer"
        case "web": return "globe"
        case "gmail", "local.draft_message": return "envelope"
        case "calendar": return "calendar"
        case "documents", "docs", "drive": return "doc"
        case "odoo.crm": return "person.crop.rectangle.stack"
        case "memory": return "brain"
        case "etsy": return "bag"
        case "sheet": return "tablecells"
        case "schedule": return "clock"
        case "channel.message": return "message"
        default: return "circle.dashed"
        }
    }
}

private struct Composer: View {
    let employee: Employee
    @Environment(WorkspaceStore.self) private var store
    @FocusState private var focused: Bool

    var body: some View {
        let busy = store.working[employee.id]?.active == true
        let text = Binding(get: { store.drafts[employee.id] ?? "" }, set: { store.drafts[employee.id] = $0 })
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField(busy ? "\(employee.name) is working — you can queue the next thing after." : "Instruct \(employee.name)…",
                          text: text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Typo.body)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1...8)
                    .focused($focused)
                    .onSubmit(send)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 5)
                    .padding(.leading, 4)
                Button(action: send) {
                    Image(systemName: store.isSending ? "ellipsis" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(Palette.void)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Palette.textFaint : Palette.text))
                }
                .buttonStyle(.plain)
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isSending)
                .help("Send (↩)")
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Palette.panel.opacity(0.9)))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(focused ? Palette.ice.opacity(0.45) : Palette.hairlineStrong, lineWidth: focused ? 1 : 0.75)
            )
            .shadow(color: focused ? Palette.ice.opacity(0.18) : .clear, radius: 18)
            HStack(spacing: 14) {
                ForEach(store.tools(for: employee.id).prefix(6)) { tool in
                    HStack(spacing: 4) {
                        Circle().fill(tool.connected ? Palette.mint : Palette.textFaint).frame(width: 5, height: 5)
                        Text(tool.name).font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                    }
                }
                Spacer()
                Text("↩ send · ⌥↩ new line").font(.system(size: 10.5)).foregroundStyle(Palette.textFaint)
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .padding(.top, 6)
        .frame(maxWidth: 860)
        .frame(maxWidth: .infinity)
        .animation(Motion.snappy, value: focused)
        .onAppear { focused = true }
    }

    private func send() {
        let body = store.drafts[employee.id] ?? ""
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        store.drafts[employee.id] = ""
        Task { await store.send(body, to: employee.id) }
    }
}

private struct ThreadInspector: View {
    let employee: Employee
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        let threads = store.threads(for: employee.id)
        let selected = store.selectedThread(for: employee.id)
        let recent = store.activity.filter { $0.employeeId == employee.id }.prefix(12)
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Eyebrow(text: "Conversations")
                    Spacer()
                    IconButton(symbol: "plus", help: "New conversation", size: 22) {
                        Task { await store.newThread(for: employee.id) }
                    }
                }
                .padding(.top, 36)
                ForEach(threads) { thread in
                    Button { Task { await store.selectThread(thread) } } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(thread.title).font(Typo.callout).foregroundStyle(Palette.text).lineLimit(1)
                                Spacer()
                                if thread.status == "archived" { Image(systemName: "archivebox").font(.system(size: 10)).foregroundStyle(Palette.textTertiary) }
                            }
                            Text("\(thread.messageCount) messages · \(TimeText.relative(thread.lastMessageAt ?? thread.createdAt))")
                                .font(Typo.caption).foregroundStyle(Palette.textTertiary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 10).fill(selected?.id == thread.id ? Color.white.opacity(0.07) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if threads.isEmpty {
                    Text("No conversations yet.").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                }
                Eyebrow(text: "Recent activity").padding(.top, 18)
                ForEach(recent) { item in
                    HStack(alignment: .top, spacing: 8) {
                        Circle().fill(Palette.status(item.kind)).frame(width: 5, height: 5).padding(.top, 6)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).font(Typo.callout).foregroundStyle(Palette.text).lineLimit(2)
                            Text(TimeText.relative(item.at)).font(Typo.caption).foregroundStyle(Palette.textTertiary)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 20)
        }
        .background(Palette.void.opacity(0.35))
    }
}

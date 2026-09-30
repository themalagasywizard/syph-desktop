import SwiftUI
import AppKit

/// The widget's content: the orb alone when collapsed; the orb in one corner of a
/// small chat when open. The chat is revealed by a circle growing out of the orb,
/// followed by a single scan-line sweep; it folds back into the orb to close.
struct DesktopWidgetView: View {
    @Environment(DesktopWidget.self) private var widget
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        ZStack(alignment: widget.corner.alignment) {
            // Always present: its reveal follows widget.expanded, so opening and closing
            // animate the same way every time (no dependence on when a view appears).
            WidgetChat()
                .allowsHitTesting(widget.expanded)
                .accessibilityHidden(!widget.expanded)
            WidgetOrb()
                .padding(DesktopWidget.pad)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: widget.corner.alignment)
    }
}

// MARK: - The orb

private struct WidgetOrb: View {
    @Environment(DesktopWidget.self) private var widget
    @Environment(WorkspaceStore.self) private var store
    @Environment(AppModel.self) private var app
    @State private var hovering = false
    @State private var dragging = false
    @State private var pressed = false

    private var employee: Employee? { store.employee(widget.employeeID) ?? store.selectedEmployee }
    private var waiting: Int { store.waitingApprovals.count }
    private var anyWorking: Bool { store.working.values.contains { $0.active } }

    private var mood: AgentOrb.Mood {
        if store.phase != .ready { return .offline }
        if waiting > 0 && !widget.expanded { return .attention }
        if let employee, widget.expanded { return AgentOrb.Mood(employee: employee, working: store.working[employee.id], waiting: false) }
        return anyWorking ? .working : .idle
    }

    private var tint: Color { widget.expanded ? (employee.map { Palette.hue(for: $0.id) } ?? Palette.ice) : Palette.ice }

    var body: some View {
        ZStack {
            // Glass disc behind the mark so it reads on any wallpaper.
            Circle()
                .fill(Palette.void.opacity(0.78))
                .background(Circle().fill(.ultraThinMaterial))
                .overlay(Circle().strokeBorder(
                    AngularGradient(colors: [tint.opacity(0.9), Palette.hairline, tint.opacity(0.35), Palette.hairline, tint.opacity(0.9)], center: .center),
                    lineWidth: hovering || widget.expanded ? 1.2 : 0.75))
                .shadow(color: tint.opacity(hovering ? 0.55 : 0.28), radius: hovering ? 14 : 9)
                .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
            AgentOrb(mood: mood, tint: tint, size: DesktopWidget.orb - 8)
            if waiting > 0 && !widget.expanded {
                Text("\(waiting)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(Palette.onSignal)
                    .frame(minWidth: 16, minHeight: 16)
                    .background(Circle().fill(Palette.amber))
                    .offset(x: 21, y: -21)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .frame(width: DesktopWidget.orb, height: DesktopWidget.orb)
        .scaleEffect(pressed ? 0.92 : (hovering && !widget.expanded ? 1.06 : 1))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: hovering)
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: pressed)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .global)
                .onChanged { value in
                    if !pressed && !dragging { pressed = true; widget.beginDrag() }
                    if !dragging && hypot(value.translation.width, value.translation.height) > 3 { dragging = true }
                    if dragging { widget.drag() }
                }
                .onEnded { _ in
                    pressed = false
                    if dragging { widget.endDrag() } else { widget.toggle() }
                    dragging = false
                }
        )
        .contextMenu {
            Button(widget.expanded ? "Close chat" : "Talk to \(employee?.name ?? "your team")") { widget.toggle() }
            Button("Open Syph") { widget.openApp() }
            Button("Command Bar  ⌥Space") { app.toggleCommandBar() }
            Divider()
            Toggle("Start in widget mode", isOn: Binding(get: { widget.startsInWidget }, set: { widget.startsInWidget = $0 }))
            Button("Hide widget") { widget.hide() }
        }
        .help(helpText)
        .accessibilityElement()
        .accessibilityLabel("Syph")
        .accessibilityHint(widget.expanded ? "Closes the chat" : "Opens a chat with your team")
        .accessibilityAddTraits(.isButton)
    }

    private var helpText: String {
        if store.phase != .ready { return "Syph — sign in to talk to your team" }
        let who = employee?.name ?? "your team"
        let state = anyWorking ? " · working" : ""
        let needs = waiting > 0 ? " · \(waiting) waiting on you" : ""
        return "Talk to \(who)\(state)\(needs). Drag to move."
    }
}

// MARK: - The chat

private struct WidgetChat: View {
    @Environment(DesktopWidget.self) private var widget
    @Environment(WorkspaceStore.self) private var store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scan: CGFloat = -0.1
    @State private var spin = 0.0

    private var employee: Employee? { store.employee(widget.employeeID) ?? store.selectedEmployee }
    private var working: WorkingRun? { employee.flatMap { store.working[$0.id] }.flatMap { $0.active ? $0 : nil } }
    private var tint: Color { employee.map { Palette.hue(for: $0.id) } ?? Palette.ice }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let origin = orbCenter(in: size)
            let reach = hypot(size.width, size.height) * 1.05
            card
                .mask {
                    Circle()
                        .frame(width: reach * 2, height: reach * 2)
                        .scaleEffect(widget.expanded ? 1 : 0.001)
                        .position(origin)
                }
                .overlay { scanLine(size: size) }
                .onAppear { if widget.expanded { sweep() } }
                .onChange(of: widget.expanded) { _, open in if open { sweep() } }
        }
    }

    /// The single scan line that crosses the card as it opens.
    private func sweep() {
        scan = -0.1
        guard !reduceMotion else { scan = 1.2; return }
        withAnimation(.easeOut(duration: 0.75).delay(0.12)) { scan = 1.2 }
    }

    /// Where the orb sits inside the chat, in the chat's own coordinates.
    private func orbCenter(in size: CGSize) -> CGPoint {
        let inset = DesktopWidget.pad + DesktopWidget.orb / 2
        let corner = widget.corner
        return CGPoint(x: corner.isLeading ? inset : size.width - inset, y: corner.isTop ? inset : size.height - inset)
    }

    /// One luminous line that sweeps across the card as it opens.
    private func scanLine(size: CGSize) -> some View {
        let fromTop = widget.corner.isTop
        let y = (fromTop ? scan : 1 - scan) * size.height
        return LinearGradient(colors: [.clear, tint.opacity(0.55), .white.opacity(0.8), tint.opacity(0.55), .clear],
                              startPoint: .leading, endPoint: .trailing)
            .frame(height: 1.2)
            .blur(radius: 0.4)
            .shadow(color: tint.opacity(0.9), radius: 6)
            .position(x: size.width / 2, y: y)
            .opacity(scan > 0 && scan < 1.1 ? 1 : 0)
            .allowsHitTesting(false)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var card: some View {
        VStack(spacing: 0) {
            if widget.corner.isTop {
                WidgetHeader(employee: employee, working: working)
                divider
                content
            } else {
                content
                divider
                WidgetHeader(employee: employee, working: working)
            }
        }
        .background(
            ZStack {
                VisualEffect(material: .hudWindow)
                Palette.void.opacity(0.72)
                RadialGradient(colors: [tint.opacity(0.16), .clear], center: widget.corner.unitPoint, startRadius: 10, endRadius: 360)
                GridLines().opacity(0.5)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(border)
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .padding(0.5)
    }

    private var content: some View {
        VStack(spacing: 0) {
            if store.phase != .ready {
                SignedOutState()
            } else if let employee {
                WidgetMessages(employee: employee, working: working)
                WidgetComposer(employee: employee, working: working)
            } else {
                Text("Hire an employee in Syph to start.").font(Typo.callout).foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var divider: some View { Rectangle().fill(Palette.hairline).frame(height: 0.5) }

    /// A hairline border that turns into a slow aurora while the employee works.
    private var border: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(
                AngularGradient(colors: working != nil
                    ? [tint, Palette.mint.opacity(0.7), Palette.violet.opacity(0.6), tint.opacity(0.3), tint]
                    : [tint.opacity(0.55), Palette.hairline, Palette.hairline, tint.opacity(0.25), tint.opacity(0.55)],
                    center: .center, angle: .degrees(spin)),
                lineWidth: working != nil ? 1.2 : 0.9)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) { spin = 360 }
            }
    }
}

private extension DesktopWidget.Corner {
    var unitPoint: UnitPoint {
        switch self {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

/// A faint technical grid, the same language as the app's backdrop.
private struct GridLines: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            let step: CGFloat = 22
            var x: CGFloat = 0
            while x < size.width { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: size.height)); x += step }
            var y: CGFloat = 0
            while y < size.height { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: size.width, y: y)); y += step }
            context.stroke(path, with: .color(Palette.overlay.opacity(0.022)), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Header

private struct WidgetHeader: View {
    let employee: Employee?
    let working: WorkingRun?
    @Environment(DesktopWidget.self) private var widget
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            if widget.corner.isLeading { Color.clear.frame(width: DesktopWidget.orb + 4) }
            if store.employees.count > 1 {
                IconButton(symbol: "chevron.left", help: "Previous employee (⇧⇥)", size: 22) { widget.cycle(-1) }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(employee?.name ?? "Syph")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.text)
                    .contentTransition(.opacity)
                Text(status)
                    .font(Typo.caption)
                    .foregroundStyle(working != nil ? Palette.mint : Palette.textTertiary)
                    .lineLimit(1)
                    .contentTransition(.opacity)
            }
            .id(employee?.id)
            .transition(.push(from: .trailing).combined(with: .opacity))
            if store.employees.count > 1 {
                IconButton(symbol: "chevron.right", help: "Next employee (⇥)", size: 22) { widget.cycle(1) }
            }
            Spacer(minLength: 4)
            IconButton(symbol: "arrow.up.forward.app", help: "Open in Syph (⌘O)", size: 26) { widget.openApp() }
            IconButton(symbol: "minus", help: "Close (esc)", size: 26) { widget.collapse() }
            if !widget.corner.isLeading { Color.clear.frame(width: DesktopWidget.orb + 4) }
        }
        .padding(.horizontal, 12)
        .frame(height: DesktopWidget.orb + DesktopWidget.pad * 2)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global)
            .onChanged { value in
                if value.translation == .zero || abs(value.translation.width) + abs(value.translation.height) < 4 { widget.beginDrag() }
                widget.drag()
            }
            .onEnded { _ in widget.endDrag() })
    }

    private var status: String {
        guard let employee else { return "" }
        if let working { return working.steps.last?.label ?? (working.phase.isEmpty ? "Working…" : working.phase.capitalized + "…") }
        if employee.isPaused { return "Paused" }
        return employee.role.isEmpty ? "Ready" : employee.role
    }
}

// MARK: - Messages

private struct WidgetMessages: View {
    let employee: Employee
    let working: WorkingRun?
    @Environment(DesktopWidget.self) private var widget
    @Environment(WorkspaceStore.self) private var store

    private var messages: [ChatMessage] { Array(store.messages(for: employee.id).suffix(30)) }
    private var approvals: [Approval] { store.waitingApprovals.filter { $0.employeeId == employee.id } }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty && working == nil {
                        EmptyChat(employee: employee)
                    }
                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, message in
                        WidgetBubble(message: message)
                            .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity), removal: .opacity))
                    }
                    ForEach(approvals) { approval in ApprovalRow(approval: approval) }
                    if let working { WorkingStrip(employee: employee, run: working) }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(14)
                .animation(.spring(response: 0.4, dampingFraction: 0.85), value: messages.count)
            }
            .scrollIndicators(.never)
            .defaultScrollAnchor(.bottom)
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: messages.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: working?.steps.count) { _, _ in withAnimation { proxy.scrollTo("end", anchor: .bottom) } }
            .onChange(of: employee.id) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
        .task(id: employee.id) {
            if store.messages(for: employee.id).isEmpty { await store.loadThread(for: employee.id) }
        }
    }
}

/// The note the widget adds for the employee is shown as a small chip, not as text.
private let contextMarker = "\n\n(Sent from the Syph widget while I’m using "

private struct WidgetBubble: View {
    let message: ChatMessage

    var body: some View {
        let parts = message.body.components(separatedBy: contextMarker)
        let text = parts[0]
        let place = parts.count > 1 ? parts[1].components(separatedBy: " on this Mac").first?.components(separatedBy: " — ").first : nil
        HStack {
            if message.isUser { Spacer(minLength: 40) }
            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                if message.isUser {
                    Text(text)
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.text)
                        .textSelection(.enabled)
                        .padding(.horizontal, 11).padding(.vertical, 7)
                        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.ice.opacity(0.16)))
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Palette.ice.opacity(0.25), lineWidth: 0.5))
                    if let place {
                        Label("in \(place)", systemImage: "scope").font(.system(size: 10)).foregroundStyle(Palette.textTertiary)
                    }
                } else {
                    let parsed = MessageParser.parse(text)
                    if !parsed.prose.isEmpty {
                        MarkdownText(source: parsed.prose)
                            .font(.system(size: 13))
                            .foregroundStyle(Palette.text)
                    }
                    ForEach(parsed.files) { file in CardChip(symbol: "doc.richtext", title: file.title, detail: file.meta) }
                    if let mail = parsed.mail {
                        CardChip(symbol: "envelope", title: mail.subject.isEmpty ? "Email draft" : mail.subject,
                                 detail: mail.status == "sent" ? "Sent to \(mail.to)" : "Draft to \(mail.to)")
                    }
                    if let crm = parsed.crmTitle { CardChip(symbol: "chart.bar.doc.horizontal", title: crm, detail: "CRM") }
                }
            }
            if !message.isUser { Spacer(minLength: 16) }
        }
    }
}

/// Files, drafts and CRM updates from a reply, as chips; the full card opens in the app.
private struct CardChip: View {
    let symbol: String
    let title: String
    let detail: String
    @Environment(DesktopWidget.self) private var widget
    @State private var hovering = false

    var body: some View {
        Button { widget.openApp() } label: {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12)).foregroundStyle(Palette.ice)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Palette.ice.opacity(0.1)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(Typo.caption.weight(.semibold)).foregroundStyle(Palette.text).lineLimit(1)
                    if !detail.isEmpty { Text(detail).font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary).lineLimit(1) }
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.forward").font(.system(size: 9, weight: .bold)).foregroundStyle(Palette.textTertiary)
            }
            .padding(7)
            .background(RoundedRectangle(cornerRadius: 10).fill(Palette.overlay.opacity(hovering ? 0.07 : 0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.hairline, lineWidth: 0.6))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("Open in Syph")
    }
}

private struct WorkingStrip: View {
    let employee: Employee
    let run: WorkingRun
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                AgentOrb(mood: .working, tint: Palette.hue(for: employee.id), size: 18)
                Text(run.goal.isEmpty ? "Working" : run.goal).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                Spacer()
                Button { Task { await store.stop(employee.id) } } label: {
                    Label("Stop", systemImage: "stop.fill").font(.system(size: 10.5, weight: .semibold))
                }
                .buttonStyle(GhostButtonStyle(compact: true))
            }
            ForEach(run.steps.suffix(3)) { step in
                HStack(spacing: 7) {
                    Image(systemName: step.status == "running" ? "circle.dotted" : (step.status == "failed" ? "xmark.circle" : "checkmark.circle"))
                        .font(.system(size: 10))
                        .foregroundStyle(step.status == "failed" ? Palette.coral : (step.status == "running" ? Palette.ice : Palette.mint))
                        .symbolEffect(.pulse, isActive: step.status == "running")
                    Text(step.label).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(1)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.overlay.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.mint.opacity(0.25), lineWidth: 0.6))
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: run.steps.count)
    }
}

private struct ApprovalRow: View {
    let approval: Approval
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(Palette.amber)
            Text(approval.title).font(Typo.caption).foregroundStyle(Palette.text).lineLimit(2)
            Spacer()
            IconButton(symbol: "xmark", help: "Decline", tint: Palette.coral, size: 22) { Task { await store.resolve(approval, approve: false) } }
            IconButton(symbol: "checkmark", help: "Approve", tint: Palette.mint, size: 22) { Task { await store.resolve(approval, approve: true) } }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 12).fill(Palette.amber.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Palette.amber.opacity(0.3), lineWidth: 0.6))
    }
}

private struct EmptyChat: View {
    let employee: Employee
    @Environment(DesktopWidget.self) private var widget

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ask \(employee.name) anything.")
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
            Text(widget.context.map { "They can work in \($0.appName) while you keep going." } ?? "Give a task, ask a question, or hand over what you're doing.")
                .font(Typo.callout).foregroundStyle(Palette.textSecondary)
            ForEach(suggestions, id: \.self) { idea in
                Button { widget.draft = idea } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkle").font(.system(size: 10)).foregroundStyle(Palette.ice)
                        Text(idea).font(Typo.caption).foregroundStyle(Palette.text)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Capsule().fill(Palette.overlay.opacity(0.05)))
                    .overlay(Capsule().strokeBorder(Palette.hairline, lineWidth: 0.6))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var suggestions: [String] {
        if let app = widget.context?.appName {
            return ["Summarise what's on my screen", "Finish what I'm doing in \(app)", "Check this for mistakes"]
        }
        return ["What are you working on?", "Summarise my day", "Draft a reply to my latest email"]
    }
}

private struct SignedOutState: View {
    @Environment(DesktopWidget.self) private var widget

    var body: some View {
        VStack(spacing: 12) {
            Text("Sign in to Syph to talk to your team.").font(Typo.callout).foregroundStyle(Palette.textSecondary)
            Button("Open Syph") { widget.openApp() }.buttonStyle(SignalButtonStyle())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Composer

private struct WidgetComposer: View {
    let employee: Employee
    let working: WorkingRun?
    @Environment(DesktopWidget.self) private var widget
    @Environment(WorkspaceStore.self) private var store
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var widget = widget
        VStack(alignment: .leading, spacing: 8) {
            if let context = widget.context {
                Button { widget.includeContext.toggle() } label: {
                    HStack(spacing: 6) {
                        if let icon = context.icon { Image(nsImage: icon).resizable().frame(width: 14, height: 14) }
                        Text(widget.includeContext ? "Here: \(context.label)" : "Not sharing what you're using")
                            .font(.system(size: 10.5))
                            .foregroundStyle(widget.includeContext ? Palette.textSecondary : Palette.textTertiary)
                            .lineLimit(1)
                        Image(systemName: widget.includeContext ? "xmark" : "plus").font(.system(size: 8, weight: .bold)).foregroundStyle(Palette.textTertiary)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Capsule().fill(Palette.overlay.opacity(widget.includeContext ? 0.06 : 0.02)))
                }
                .buttonStyle(.plain)
                .help(widget.includeContext ? "\(employee.name) is told which app and window you're in. Click to leave it out." : "Tell \(employee.name) which app you're in.")
                .transition(.opacity)
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField(working != nil ? "\(employee.name) is working…" : "Tell \(employee.name) what to do…", text: $widget.draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Palette.text)
                    .lineLimit(1...5)
                    .focused($focused)
                    .onSubmit { send() }
                    .disabled(employee.isPaused)
                Button(action: send) {
                    Image(systemName: store.isSending ? "circle.dotted" : "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(canSend ? Palette.onSignal : Palette.textTertiary)
                        .frame(width: 26, height: 26)
                        .background(Circle().fill(canSend ? AnyShapeStyle(Palette.signal) : AnyShapeStyle(Palette.overlay.opacity(0.06))))
                        .symbolEffect(.pulse, isActive: store.isSending)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 12).padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.field))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(focused ? Palette.ice.opacity(0.45) : Palette.hairline, lineWidth: 0.75))
            if let toast = store.toast ?? store.errorMessage {
                Text(toast).font(Typo.caption).foregroundStyle(Palette.amber).lineLimit(2)
            }
        }
        .padding(12)
        .onAppear { focused = true }
        .onChange(of: employee.id) { _, _ in focused = true }
        .onKeyPress(.tab) { widget.cycle(NSEvent.modifierFlags.contains(.shift) ? -1 : 1); return .handled }
        .onKeyPress(.escape) { widget.collapse(); return .handled }
        .onKeyPress(characters: .init(charactersIn: "o"), phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            widget.openApp()
            return .handled
        }
    }

    private var canSend: Bool {
        !widget.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !store.isSending && working == nil && !employee.isPaused
    }

    private func send() {
        guard canSend else { return }
        Task { await widget.send() }
    }
}

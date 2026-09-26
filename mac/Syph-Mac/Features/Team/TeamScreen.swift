import SwiftUI

struct TeamScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store
    @State private var focusedID: String?

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(eyebrow: "Team", title: "\(store.employees.count) AI employee\(store.employees.count == 1 ? "" : "s")",
                             detail: "Each one has a mission, a schedule, tools and limits. They share the company Brain.") {
                    HStack(spacing: 8) {
                        Button { Task { await store.pauseAll() } } label: { Label("Pause all", systemImage: "pause.circle") }
                            .buttonStyle(GhostButtonStyle(compact: true))
                        Button { app.showHire = true } label: { Label("Hire", systemImage: "plus") }
                            .buttonStyle(SignalButtonStyle(compact: true))
                    }
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 250, maximum: 360), spacing: 14)], spacing: 14) {
                        ForEach(store.employees) { employee in
                            EmployeeTile(employee: employee, selected: focused?.id == employee.id)
                                .onTapGesture { withAnimation(Motion.snappy) { focusedID = employee.id } }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            if let employee = focused {
                Rectangle().fill(Palette.hairline).frame(width: 0.5)
                EmployeeDetail(employee: employee)
                    .frame(width: 380)
                    .id(employee.id)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
    }

    private var focused: Employee? {
        store.employees.first { $0.id == focusedID } ?? store.employees.first
    }
}

private struct EmployeeTile: View {
    let employee: Employee
    let selected: Bool
    @Environment(WorkspaceStore.self) private var store
    @State private var hovering = false

    var body: some View {
        let waiting = store.waitingApprovals.contains { $0.employeeId == employee.id }
        let run = store.working[employee.id]
        let tint = Palette.hue(for: employee.id)
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                AgentOrb(mood: .init(employee: employee, working: run, waiting: waiting), tint: tint, size: 54)
                Spacer()
                Chip(text: employee.autonomyLevel.capitalized, color: Palette.textSecondary)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(employee.name).font(.system(size: 16, weight: .semibold)).foregroundStyle(Palette.text)
                Text(employee.role).font(Typo.caption).foregroundStyle(tint.opacity(0.9))
            }
            Text(employee.missionTitle.isEmpty ? employee.mission : employee.missionTitle)
                .font(Typo.callout).foregroundStyle(Palette.textSecondary).lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                StatusDot(color: waiting ? Palette.amber : (run?.active == true ? Palette.ice : (employee.isPaused ? Palette.textTertiary : Palette.mint)),
                          pulsing: run?.active == true, size: 5)
                Text(waiting ? "Needs you" : (run?.active == true ? (run?.goal ?? "Working") : (employee.isPaused ? "Paused" : "Ready")))
                    .font(Typo.caption).foregroundStyle(Palette.textTertiary).lineLimit(1)
                Spacer()
                Text("\(employee.toolIds.count) tools").font(Typo.caption).foregroundStyle(Palette.textFaint)
            }
        }
        .card(radius: 18, padding: 18, highlighted: selected || hovering)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(selected ? tint.opacity(0.5) : .clear, lineWidth: 1)
        )
        .scaleEffect(hovering ? 1.01 : 1)
        .onHover { hovering = $0 }
        .animation(Motion.snappy, value: hovering)
        .contentShape(Rectangle())
    }
}

private struct EmployeeDetail: View {
    let employee: Employee
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        let tools = store.tools(for: employee.id)
        let jobs = store.jobs.filter { $0.employeeId == employee.id }
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 14) {
                    AgentOrb(mood: .init(employee: employee, working: store.working[employee.id], waiting: false),
                             tint: Palette.hue(for: employee.id), size: 60)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(employee.name).font(Typo.title).foregroundStyle(Palette.text)
                        Text(employee.role).font(Typo.callout).foregroundStyle(Palette.textSecondary)
                    }
                }
                .padding(.top, 36)
                HStack(spacing: 8) {
                    Button { store.select(employee); app.go(.chat) } label: { Label("Message", systemImage: "bubble.left") }
                        .buttonStyle(SignalButtonStyle(compact: true))
                    Button { Task { await store.wake(employee.id) } } label: { Label("Wake", systemImage: "sun.max") }
                        .buttonStyle(GhostButtonStyle(compact: true))
                    Button {
                        Task { if employee.isPaused { await store.resume(employee.id) } else { await store.pause(employee.id) } }
                    } label: {
                        Label(employee.isPaused ? "Resume" : "Pause", systemImage: employee.isPaused ? "play" : "pause")
                    }
                    .buttonStyle(GhostButtonStyle(compact: true))
                }
                field("Mission", employee.mission)
                if !employee.success.isEmpty { field("What success looks like", employee.success) }
                if !employee.personality.isEmpty { field("How they work", employee.personality) }

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Autonomy")
                    Picker("", selection: Binding(
                        get: { employee.autonomyLevel },
                        set: { value in Task { await store.patch(employee.id, ["autonomy": value]) } })) {
                        Text("Careful").tag("conservative")
                        Text("Balanced").tag("balanced")
                        Text("Bold").tag("autonomous")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Eyebrow(text: "Tools")
                    ForEach(store.accountTools) { tool in
                        let assigned = employee.toolIds.contains(tool.id)
                        let detail = tools.first { $0.id == tool.id }
                        HStack(spacing: 10) {
                            Image(systemName: Self.symbol(tool.id)).frame(width: 18).foregroundStyle(assigned ? Palette.ice : Palette.textTertiary)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(tool.name).font(Typo.callout).foregroundStyle(Palette.text)
                                if let detail {
                                    Text("read \(detail.read) · write \(detail.write)").font(.system(size: 10.5)).foregroundStyle(Palette.textTertiary)
                                } else if !tool.connected {
                                    Text("Not connected").font(.system(size: 10.5)).foregroundStyle(Palette.textFaint)
                                }
                            }
                            Spacer()
                            Toggle("", isOn: Binding(get: { assigned }, set: { value in
                                Task { await store.setTool(tool.id, enabled: value, for: employee) }
                            }))
                            .toggleStyle(.switch)
                            .controlSize(.mini)
                            .labelsHidden()
                        }
                        .padding(.vertical, 3)
                    }
                }

                if !jobs.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Eyebrow(text: "Schedule")
                        ForEach(jobs) { job in
                            HStack {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(job.title).font(Typo.callout).foregroundStyle(Palette.text)
                                    Text(job.scheduleDisplay).font(Typo.caption).foregroundStyle(Palette.textTertiary)
                                }
                                Spacer()
                                Text(TimeText.relative(job.nextRunAt)).font(Typo.caption).foregroundStyle(Palette.textTertiary)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 24)
        }
        .background(Palette.void.opacity(0.35))
    }

    private func field(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Eyebrow(text: title)
            Text(text).font(Typo.body).foregroundStyle(Palette.text.opacity(0.88)).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    static func symbol(_ id: String) -> String {
        switch id {
        case "gmail": return "envelope"
        case "whatsapp", "telegram": return "message"
        case "drive": return "externaldrive"
        case "docs": return "doc.text"
        case "calendar": return "calendar"
        case "web": return "globe"
        case "sheet": return "tablecells"
        case "records": return "person.text.rectangle"
        case "odoo": return "person.crop.rectangle.stack"
        case "etsy": return "bag"
        case "computer": return "desktopcomputer"
        case "documents": return "folder"
        case "presenton": return "rectangle.on.rectangle"
        default: return "wrench.and.screwdriver"
        }
    }
}

struct HireSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(WorkspaceStore.self) private var store
    @Environment(AppModel.self) private var app
    @State private var input = HireInput()
    @State private var step = 0
    @State private var busy = false
    @State private var error: String?

    private let roles: [(String, String, String)] = [
        ("Sales", "Market & Sales", "Find qualified buyers, keep the pipeline honest, follow up, and surface only the decisions that need me."),
        ("Marketing", "Marketing", "Research the market, draft campaigns, and keep a brief ready before anyone asks."),
        ("Assistant", "Executive assistant", "Keep the inbox, calendar and follow-ups from eating the week. Interrupt only when time or money is at stake."),
        ("Operator", "Operations", "Work on my Mac: keep files organised, prepare documents and run the routine desktop chores I hand over."),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Eyebrow(text: "Hire · step \(step + 1) of 2", color: Palette.ice)
                    Text(step == 0 ? "What will they own?" : "How should they work?").font(Typo.display(22)).foregroundStyle(Palette.text)
                }
                Spacer()
                AgentOrb(mood: busy ? .working : .idle, tint: Palette.ice, size: 44)
            }
            .padding(24)
            .hairlineBottom()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if step == 0 { missionStep } else { workStep }
                }
                .padding(24)
            }
            .frame(height: 400)

            HStack {
                if let error { Text(error).font(Typo.caption).foregroundStyle(Palette.coral) }
                Spacer()
                Button(step == 0 ? "Cancel" : "Back") { if step == 0 { dismiss() } else { step = 0 } }
                    .buttonStyle(GhostButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(step == 0 ? "Continue" : (busy ? "Hiring…" : "Hire \(input.name.isEmpty ? "employee" : input.name)")) {
                    if step == 0 { step = 1 } else { hire() }
                }
                .buttonStyle(SignalButtonStyle())
                .disabled(input.mission.trimmingCharacters(in: .whitespaces).count < 8 || busy)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            .overlay(alignment: .top) { Rectangle().fill(Palette.hairline).frame(height: 0.5) }
        }
        .frame(width: 620)
        .background(Palette.panel)
        .animation(Motion.snappy, value: step)
    }

    private var missionStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: "Start from a role")
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                ForEach(roles, id: \.0) { role in
                    Button {
                        input.role = role.1
                        input.mission = role.2
                        if role.0 == "Operator" && !input.toolIds.contains("computer") { input.toolIds.append("computer") }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(role.0).font(Typo.headline).foregroundStyle(Palette.text)
                            Text(role.2).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(2)
                                .multilineTextAlignment(.leading)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .card(radius: 12, padding: 12, highlighted: input.role == role.1)
                    }
                    .buttonStyle(.plain)
                }
            }
            Eyebrow(text: "Name (optional)")
            SyphTextField(title: "We’ll pick one if you leave this empty", text: $input.name)
            Eyebrow(text: "Mission")
            TextEditor(text: $input.mission)
                .font(Typo.body).scrollContentBackground(.hidden)
                .frame(height: 80).padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Palette.field))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Palette.hairline, lineWidth: 0.75))
            Eyebrow(text: "What success looks like")
            SyphTextField(title: "e.g. Three qualified meetings a week", text: $input.success)
        }
    }

    private var workStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Eyebrow(text: "Autonomy")
            Picker("", selection: $input.autonomy) {
                Text("Careful — ask before acting").tag("conservative")
                Text("Balanced").tag("balanced")
                Text("Bold — only irreversible steps wait").tag("autonomous")
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            Eyebrow(text: "Wakes up")
            Picker("", selection: $input.wakeCadence) {
                Text("Only when asked").tag("off")
                Text("Every morning").tag("daily_morning")
                Text("Twice a day").tag("12h")
                Text("Every hour").tag("1h")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Eyebrow(text: "Tools")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading, spacing: 8) {
                ForEach(store.accountTools) { tool in
                    let on = input.toolIds.contains(tool.id)
                    Button {
                        if on { input.toolIds.removeAll { $0 == tool.id } } else { input.toolIds.append(tool.id) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Palette.ice : Palette.textTertiary)
                            Text(tool.name).font(Typo.callout).foregroundStyle(Palette.text).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(on ? Palette.ice.opacity(0.08) : Palette.field))
                    }
                    .buttonStyle(.plain)
                }
            }
            if input.toolIds.contains("computer") {
                Label("They can use this Mac within the scopes you set in This Mac. Every action shows on screen.",
                      systemImage: "desktopcomputer")
                    .font(Typo.caption).foregroundStyle(Palette.mint)
            }
            Eyebrow(text: "Personality (optional)")
            SyphTextField(title: "Direct, warm, brief", text: $input.personality)
        }
    }

    private func hire() {
        busy = true
        error = nil
        Task {
            do {
                let employee = try await store.hire(input)
                store.toast = "\(employee.name) joined your team."
                busy = false
                dismiss()
                app.go(.chat)
            } catch {
                self.error = error.localizedDescription
                busy = false
            }
        }
    }
}

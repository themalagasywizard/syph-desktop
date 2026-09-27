import SwiftUI
import AppKit

struct WorkScreen: View {
    @Environment(WorkspaceStore.self) private var store
    @State private var filter: String?

    var body: some View {
        let items = store.activity.filter { filter == nil || $0.employeeId == filter }
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(eyebrow: "Work", title: "Every step, on the record",
                             detail: "What your team did, newest first.") {
                    Menu {
                        Button("Everyone") { filter = nil }
                        Divider()
                        ForEach(store.employees) { employee in Button(employee.name) { filter = employee.id } }
                    } label: {
                        Label(store.employee(filter)?.name ?? "Everyone", systemImage: "line.3.horizontal.decrease")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            TimelineRow(item: item, last: index == items.count - 1)
                        }
                        if items.isEmpty {
                            EmptyState(symbol: "waveform.path.ecg", title: "Quiet so far", detail: "Activity appears as your employees work.")
                                .frame(height: 280)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            Rectangle().fill(Palette.hairline).frame(width: 0.5)
            SchedulePanel().frame(width: 340)
        }
    }
}

private struct TimelineRow: View {
    let item: Activity
    let last: Bool
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(TimeText.clock(item.at))
                .font(Typo.mono).foregroundStyle(Palette.textTertiary)
                .frame(width: 92, alignment: .trailing)
                .padding(.top, 2)
            VStack(spacing: 0) {
                Circle().fill(Palette.status(item.kind)).frame(width: 7, height: 7).padding(.top, 5)
                    .shadow(color: Palette.status(item.kind), radius: 3)
                if !last { Rectangle().fill(Palette.hairline).frame(width: 0.75).frame(maxHeight: .infinity) }
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    if let employee = store.employee(item.employeeId) {
                        Text(employee.name).font(.system(size: 11.5, weight: .semibold)).foregroundStyle(Palette.hue(for: employee.id))
                    }
                    Text(item.title).font(Typo.callout).foregroundStyle(Palette.text)
                }
                if !item.summary.isEmpty {
                    Text(item.summary).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(3)
                }
            }
            .padding(.bottom, 18)
            Spacer(minLength: 0)
        }
    }
}

private struct SchedulePanel: View {
    @Environment(WorkspaceStore.self) private var store

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Eyebrow(text: "Recurring work").padding(.top, 44)
                if store.jobs.isEmpty {
                    Text("No schedules yet. Ask an employee to do something “every Monday at 9” and it appears here.")
                        .font(Typo.caption).foregroundStyle(Palette.textTertiary)
                }
                ForEach(store.jobs) { job in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(job.title).font(Typo.headline).foregroundStyle(job.enabled ? Palette.text : Palette.textTertiary).lineLimit(2)
                            Spacer()
                            Toggle("", isOn: Binding(get: { job.enabled }, set: { value in Task { await store.setJob(job, enabled: value) } }))
                                .toggleStyle(.switch).controlSize(.mini).labelsHidden()
                        }
                        Text(job.scheduleDisplay).font(Typo.caption).foregroundStyle(Palette.ice)
                        if !job.instruction.isEmpty {
                            Text(job.instruction).font(Typo.caption).foregroundStyle(Palette.textSecondary).lineLimit(3)
                        }
                        HStack {
                            Text(store.employee(job.employeeId)?.name ?? "").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                            Spacer()
                            if job.enabled, let next = job.nextRunAt {
                                Text((TimeText.date(next) ?? .distantFuture) < Date() ? "due now" : "next \(TimeText.relative(next))").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                            }
                            IconButton(symbol: "trash", help: "Delete schedule", size: 20) { Task { await store.deleteJob(job) } }
                        }
                    }
                    .card(radius: 12, padding: 12)
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 20)
        }
        .background(Palette.void.opacity(0.3))
    }
}

struct LibraryScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(WorkspaceStore.self) private var store
    @State private var query = ""
    @State private var folder = ""
    @State private var listing: DocumentListing?
    @State private var selected: LibraryDocument?
    @State private var loading = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(eyebrow: "Library", title: "Documents", detail: "Everything your employees wrote, researched and built.")
                HStack(spacing: 8) {
                    SyphTextField(title: "Search documents", text: $query, symbol: "magnifyingglass")
                        .onSubmit { Task { await load() } }
                    Menu {
                        Button("All folders") { folder = "" }
                        ForEach(listing?.folders ?? [], id: \.self) { name in Button(name) { folder = name } }
                    } label: {
                        Label(folder.isEmpty ? "All" : folder, systemImage: "folder")
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                ScrollView {
                    VStack(spacing: 4) {
                        if loading && listing == nil { ProgressView().padding(40) }
                        ForEach(listing?.documents ?? []) { doc in
                            Button { Task { await open(doc) } } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: icon(doc.format)).foregroundStyle(Palette.ice).frame(width: 20).padding(.top, 2)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(doc.title).font(Typo.callout).foregroundStyle(Palette.text).lineLimit(1)
                                        Text("\(doc.folder) · \(TimeText.relative(doc.updatedAt))").font(Typo.caption).foregroundStyle(Palette.textTertiary)
                                    }
                                    Spacer()
                                }
                                .padding(10)
                                .background(RoundedRectangle(cornerRadius: 10).fill(selected?.id == doc.id ? Palette.overlay.opacity(0.07) : .clear))
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                        if listing?.documents.isEmpty == true {
                            EmptyState(symbol: "books.vertical", title: "No documents", detail: "Reports, decks and notes appear here.").frame(height: 240)
                        }
                    }
                    .padding(.horizontal, 12)
                }
            }
            .frame(width: 400)
            Rectangle().fill(Palette.hairline).frame(width: 0.5)
            Group {
                if let doc = selected {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            Eyebrow(text: doc.folder, color: Palette.ice)
                            Text(doc.title).font(Typo.display(26)).foregroundStyle(Palette.text)
                            HStack(spacing: 8) {
                                ForEach(doc.downloads, id: \.format) { download in
                                    Button(download.format.uppercased()) {
                                        if let url = app.api.resolve(download.url) { NSWorkspace.shared.open(url) }
                                    }
                                    .buttonStyle(GhostButtonStyle(compact: true))
                                }
                            }
                            Rectangle().fill(Palette.hairline).frame(height: 0.5)
                            MarkdownText(source: doc.content ?? doc.excerpt)
                        }
                        .padding(36)
                        .frame(maxWidth: 780, alignment: .leading)
                    }
                } else {
                    EmptyState(symbol: "doc.text.magnifyingglass", title: "Pick a document", detail: "Preview it here, or download it in the format you need.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task { await load() }
        .onChange(of: folder) { _, _ in Task { await load() } }
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do { listing = try await store.documents(query: query, folder: folder) }
        catch { store.errorMessage = error.localizedDescription }
    }

    private func open(_ doc: LibraryDocument) async {
        selected = doc
        if let full = try? await store.document(doc.id) { selected = full }
    }

    private func icon(_ format: String) -> String {
        switch format {
        case "pptx", "deck": return "rectangle.on.rectangle"
        case "pdf": return "doc.richtext"
        case "csv", "xlsx": return "tablecells"
        default: return "doc.text"
        }
    }
}

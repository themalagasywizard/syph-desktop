import Foundation
import Observation

/// Everything the workspace shows, loaded from the same API as web and iPhone.
@MainActor
@Observable
final class WorkspaceStore {
    enum Phase: Equatable { case restoring, signedOut, loading, ready }

    let api: APIClient

    var phase: Phase = .restoring
    var user: SyphUser?
    var employees: [Employee] = []
    var approvals: [Approval] = []
    var activity: [Activity] = []
    var jobs: [WakeJob] = []
    var conversations: [Conversation] = []
    var messages: [ChatMessage] = []
    var accountTools: [ConnectedTool] = []
    var employeeTools: [ConnectedTool] = []
    var working: [String: WorkingRun] = [:]
    var selectedEmployeeID: String?
    var selectedThreadIDs: [String: String] = [:]
    var drafts: [String: String] = [:]
    var isSending = false
    var isSigningIn = false
    var errorMessage: String?
    var toast: String?
    var lastRefresh: Date?

    var llmProviders: [LlmProvider] = []
    var llmSettings: LlmSettings?

    @ObservationIgnored var onRefresh: (() -> Void)?
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var pollTasks: [String: Task<Void, Never>] = [:]

    init(api: APIClient) {
        self.api = api
    }

    // MARK: Derived

    var selectedEmployee: Employee? {
        employees.first(where: { $0.id == selectedEmployeeID }) ?? employees.first
    }

    var waitingApprovals: [Approval] { approvals.filter { $0.status == "waiting" } }

    var activeEmployeeCount: Int { working.values.filter(\.active).count }

    func employee(_ id: String?) -> Employee? { employees.first { $0.id == id } }

    func threads(for employeeID: String) -> [Conversation] {
        conversations.filter { $0.employeeId == employeeID }
            .sorted { ($0.lastMessageAt ?? $0.createdAt) > ($1.lastMessageAt ?? $1.createdAt) }
    }

    func selectedThread(for employeeID: String) -> Conversation? {
        if let id = selectedThreadIDs[employeeID], let thread = conversations.first(where: { $0.id == id }) {
            return thread
        }
        return conversations.first { $0.employeeId == employeeID && $0.status == "active" }
    }

    func messages(for employeeID: String) -> [ChatMessage] {
        guard let thread = selectedThread(for: employeeID) else {
            return messages.filter { $0.employeeId == employeeID && $0.conversationId == nil }.sorted { $0.at < $1.at }
        }
        return messages.filter { $0.conversationId == thread.id }.sorted { $0.at < $1.at }
    }

    func tools(for employeeID: String) -> [ConnectedTool] {
        employeeTools.filter { $0.employeeId == employeeID }
    }

    var computerTool: ConnectedTool? { accountTools.first { $0.id == "computer" } }

    // MARK: Session

    func restore() async {
        phase = .restoring
        do {
            _ = try await api.send(SyphUser.self, "/api/v1/auth/me")
            phase = .loading
            try await loadWorkspace()
            phase = .ready
            startAutoRefresh()
        } catch let error as APIError where error.statusCode == 401 {
            phase = .signedOut
        } catch {
            errorMessage = error.localizedDescription
            phase = .signedOut
        }
    }

    func signIn(email: String, password: String) async {
        isSigningIn = true
        errorMessage = nil
        defer { isSigningIn = false }
        do {
            _ = try await api.send(SyphUser.self, "/api/v1/auth/login", method: "POST",
                                   body: ["email": email, "password": password])
            phase = .loading
            try await loadWorkspace()
            phase = .ready
            startAutoRefresh()
        } catch {
            errorMessage = error.localizedDescription
            phase = .signedOut
        }
    }

    func signOut() async {
        refreshTask?.cancel()
        pollTasks.values.forEach { $0.cancel() }
        pollTasks = [:]
        _ = try? await api.send(EmptyResponse.self, "/api/v1/auth/logout", method: "POST")
        user = nil
        employees = []; approvals = []; activity = []; jobs = []
        conversations = []; messages = []; working = [:]
        phase = .signedOut
    }

    // MARK: Loading

    func loadWorkspace() async throws {
        let payload = try await api.send(WorkspacePayload.self, "/api/v1/workspace")
        user = payload.user
        employees = payload.employees
        approvals = payload.approvals
        activity = payload.activity
        jobs = payload.jobs
        let incoming = Set(payload.conversations.map(\.id))
        conversations = payload.conversations + conversations.filter { !incoming.contains($0.id) }
        // Keep thread transcripts we already fetched; the payload only carries recent messages.
        let payloadIDs = Set(payload.messages.map(\.id))
        messages = payload.messages + messages.filter { !payloadIDs.contains($0.id) }
        accountTools = payload.accountTools
        employeeTools = payload.employeeTools
        if selectedEmployeeID == nil || employee(selectedEmployeeID) == nil {
            selectedEmployeeID = employees.first?.id
        }
        lastRefresh = Date()
        onRefresh?()
        if let id = selectedEmployee?.id {
            await refreshWorking(id)
            await loadThread(for: id)
        }
    }

    func refresh() async {
        do {
            try await loadWorkspace()
            if errorMessage != nil { errorMessage = nil }
        } catch let error as APIError where error.statusCode == 401 {
            phase = .signedOut
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func startAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(12))
                guard let self, !Task.isCancelled, self.phase == .ready else { continue }
                await self.refresh()
            }
        }
    }

    func select(_ employee: Employee) {
        guard employee.id != selectedEmployeeID else { return }
        selectedEmployeeID = employee.id
        Task {
            await refreshWorking(employee.id)
            await loadThread(for: employee.id)
        }
    }

    func loadThread(for employeeID: String) async {
        guard let thread = selectedThread(for: employeeID) else { return }
        do {
            let detail = try await api.send(ConversationDetail.self, "/api/v1/conversations/\(thread.id)")
            messages = messages.filter { $0.conversationId != thread.id } + detail.messages
            if let index = conversations.firstIndex(where: { $0.id == thread.id }) {
                conversations[index] = detail.conversation
            }
        } catch {
            // The thread stays on what the workspace payload carried.
        }
    }

    func selectThread(_ conversation: Conversation) async {
        selectedThreadIDs[conversation.employeeId] = conversation.id
        await loadThread(for: conversation.employeeId)
    }

    func newThread(for employeeID: String) async {
        do {
            let thread = try await api.send(Conversation.self, "/api/v1/employees/\(employeeID)/conversations",
                                            method: "POST", body: [String: String]())
            conversations.insert(thread, at: 0)
            selectedThreadIDs[employeeID] = thread.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: Working state

    func refreshWorking(_ employeeID: String) async {
        do {
            let run = try await api.send(WorkingRun.self, "/api/v1/employees/\(employeeID)/working")
            working[employeeID] = run
            if run.active { beginPolling(employeeID) }
        } catch {}
    }

    private func beginPolling(_ employeeID: String) {
        guard pollTasks[employeeID] == nil else { return }
        pollTasks[employeeID] = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(1500))
                guard let self, !Task.isCancelled else { break }
                do {
                    let run = try await self.api.send(WorkingRun.self, "/api/v1/employees/\(employeeID)/working")
                    self.working[employeeID] = run
                    if !run.active {
                        await self.loadThread(for: employeeID)
                        await self.refresh()
                        break
                    }
                } catch { break }
            }
            self?.pollTasks[employeeID] = nil
        }
    }

    // MARK: Commands

    @discardableResult
    func send(_ text: String, to employeeID: String) async -> Bool {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isSending else { return false }
        if working[employeeID]?.active == true {
            toast = "Still working — wait for the current task or stop it."
            return false
        }
        isSending = true
        errorMessage = nil
        defer { isSending = false }
        do {
            var thread = selectedThread(for: employeeID)
            if thread == nil || thread?.status == "archived" {
                thread = try await api.send(Conversation.self, "/api/v1/employees/\(employeeID)/conversations",
                                            method: "POST", body: [String: String]())
                if let thread {
                    conversations.insert(thread, at: 0)
                    selectedThreadIDs[employeeID] = thread.id
                }
            }
            var payload: [String: String] = ["body": body]
            if let id = thread?.id { payload["conversationId"] = id }
            // Optimistic echo so the message lands instantly.
            let echo = ChatMessage(id: "local-\(UUID().uuidString)", employeeId: employeeID, conversationId: thread?.id,
                                   role: "user", body: body, at: ISO8601DateFormatter().string(from: Date()))
            messages.append(echo)
            let response = try await api.send(CommandResponse.self, "/api/v1/employees/\(employeeID)/instructions",
                                              method: "POST", body: payload, idempotent: true, timeout: 180)
            working[employeeID] = WorkingRun(active: true, runId: response.runId, status: "working",
                                             goal: body, phase: "starting", steps: [])
            beginPolling(employeeID)
            await loadThread(for: employeeID)
            messages.removeAll { $0.id == echo.id }
            return true
        } catch {
            messages.removeAll { $0.id.hasPrefix("local-") }
            errorMessage = error.localizedDescription
            drafts[employeeID] = body
            return false
        }
    }

    func stop(_ employeeID: String) async {
        let runQuery = working[employeeID]?.runId.map { "?run_id=\($0)" } ?? ""
        _ = try? await api.send(CommandResponse.self, "/api/v1/employees/\(employeeID)/working/cancel\(runQuery)",
                                method: "POST", idempotent: true)
        await refreshWorking(employeeID)
    }

    @discardableResult
    func resolve(_ approval: Approval, approve: Bool) async -> Bool {
        do {
            _ = try await api.send(CommandResponse.self, "/api/v1/approvals/\(approval.id)/\(approve ? "approve" : "reject")",
                                   method: "POST", idempotent: true)
            if let index = approvals.firstIndex(where: { $0.id == approval.id }) {
                approvals[index].status = approve ? "approved" : "rejected"
            }
            toast = approve ? "Approved — \(employee(approval.employeeId)?.name ?? "they") will carry on." : "Declined."
            if approve { await refreshWorking(approval.employeeId) }
            await refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func hire(_ input: HireInput) async throws -> Employee {
        let employee = try await api.send(Employee.self, "/api/v1/employees", method: "POST", body: input.body, idempotent: true)
        try await loadWorkspace()
        selectedEmployeeID = employee.id
        return employee
    }

    func patch(_ employeeID: String, _ fields: [String: Any]) async {
        do {
            _ = try await api.send(Employee.self, "/api/v1/employees/\(employeeID)", method: "PATCH", body: fields)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setTool(_ toolID: String, enabled: Bool, for employee: Employee) async {
        var ids = employee.toolIds
        if enabled { if !ids.contains(toolID) { ids.append(toolID) } } else { ids.removeAll { $0 == toolID } }
        guard !ids.isEmpty else { errorMessage = "Each employee needs at least one tool."; return }
        await patch(employee.id, ["toolIds": ids])
    }

    func pause(_ employeeID: String) async { await command("/api/v1/employees/\(employeeID)/pause") }
    func resume(_ employeeID: String) async { await command("/api/v1/employees/\(employeeID)/resume") }
    func wake(_ employeeID: String) async {
        await command("/api/v1/employees/\(employeeID)/wakeup")
        await refreshWorking(employeeID)
    }
    func pauseAll() async { await command("/api/v1/workspace/pause-all") }

    private func command(_ path: String) async {
        do {
            _ = try await api.send(CommandResponse.self, path, method: "POST", idempotent: true)
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setJob(_ job: WakeJob, enabled: Bool) async {
        do {
            _ = try await api.send(WakeJob.self, "/api/v1/employees/\(job.employeeId)/jobs/\(job.id)", method: "PATCH", body: ["enabled": enabled])
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func deleteJob(_ job: WakeJob) async {
        do {
            _ = try await api.send(EmptyResponse.self, "/api/v1/employees/\(job.employeeId)/jobs/\(job.id)", method: "DELETE")
            jobs.removeAll { $0.id == job.id }
        } catch { errorMessage = error.localizedDescription }
    }

    // MARK: Library

    func documents(query: String, folder: String) async throws -> DocumentListing {
        var items = [URLQueryItem(name: "offset", value: "0")]
        if !query.isEmpty { items.append(URLQueryItem(name: "q", value: query)) }
        if !folder.isEmpty { items.append(URLQueryItem(name: "folder", value: folder)) }
        var comps = URLComponents()
        comps.queryItems = items
        return try await api.send(DocumentListing.self, "/api/v1/documents?\(comps.percentEncodedQuery ?? "")")
    }

    func document(_ id: String) async throws -> LibraryDocument {
        try await api.send(LibraryDocument.self, "/api/v1/documents/\(id)")
    }

    // MARK: Settings

    func loadModelSettings() async {
        llmProviders = (try? await api.send([LlmProvider].self, "/api/v1/settings/llm/providers")) ?? llmProviders
        llmSettings = (try? await api.send(LlmSettings.self, "/api/v1/settings/llm")) ?? llmSettings
    }

    func saveModel(provider: String, model: String, apiKey: String) async throws {
        var body: [String: Any] = ["provider": provider, "model": model, "baseUrl": llmSettings?.baseUrl ?? "",
                                   "fallbackModels": llmSettings?.fallbackModels ?? []]
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { body["apiKey"] = key }
        llmSettings = try await api.send(LlmSettings.self, "/api/v1/settings/llm", method: "PUT", body: body)
    }

    func testModel() async throws -> SettingsResult {
        try await api.send(SettingsResult.self, "/api/v1/settings/llm/test", method: "POST")
    }

    func connectURL(_ path: String) async throws -> URL? {
        let result = try await api.send(ConnectResult.self, path, method: "POST", body: [String: String]())
        return URL(string: result.url)
    }
}

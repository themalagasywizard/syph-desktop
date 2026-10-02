import Foundation

// Wire models for the Syph (Jarvis) API. Keys are camelCase on the wire.
// Decoders default optional-in-practice fields so older servers still load.

struct SyphUser: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let email: String
    let role: String
}

struct Employee: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let role: String
    let missionTitle: String
    let mission: String
    let success: String
    let personality: String
    let userContext: String
    let status: String
    let currentTaskTitle: String
    let autonomyLevel: String
    let wakeCadence: String
    let timezone: String
    let workingSince: String
    let nextWakeAt: String?
    let toolIds: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name, role, missionTitle, mission, success, personality, userContext, status, currentTaskTitle
        case autonomyLevel, wakeCadence, timezone, workingSince, nextWakeAt, toolIds
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        role = try c.decodeIfPresent(String.self, forKey: .role) ?? ""
        missionTitle = try c.decodeIfPresent(String.self, forKey: .missionTitle) ?? ""
        mission = try c.decodeIfPresent(String.self, forKey: .mission) ?? ""
        success = try c.decodeIfPresent(String.self, forKey: .success) ?? ""
        personality = try c.decodeIfPresent(String.self, forKey: .personality) ?? ""
        userContext = try c.decodeIfPresent(String.self, forKey: .userContext) ?? ""
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "idle"
        currentTaskTitle = try c.decodeIfPresent(String.self, forKey: .currentTaskTitle) ?? ""
        autonomyLevel = try c.decodeIfPresent(String.self, forKey: .autonomyLevel) ?? "balanced"
        wakeCadence = try c.decodeIfPresent(String.self, forKey: .wakeCadence) ?? "12h"
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone) ?? "Europe/Berlin"
        workingSince = try c.decodeIfPresent(String.self, forKey: .workingSince) ?? ""
        nextWakeAt = try c.decodeIfPresent(String.self, forKey: .nextWakeAt)
        toolIds = try c.decodeIfPresent([String].self, forKey: .toolIds) ?? []
    }

    var initial: String { String(name.prefix(1)).uppercased() }
    var isPaused: Bool { status == "paused" }
}

struct HireInput {
    var name: String = ""
    var role: String = ""
    var mission: String = ""
    var success: String = ""
    var personality: String = ""
    var userContext: String = ""
    var toolIds: [String] = ["records", "web", "documents"]
    var autonomy: String = "balanced"
    var wakeCadence: String = "off"
    var timezone: String = TimeZone.current.identifier

    var body: [String: Any] {
        var body: [String: Any] = [
            "mission": mission, "success": success, "toolIds": toolIds, "toolAccess": [String: String](),
            "autonomy": autonomy, "role": role, "personality": personality, "userContext": userContext,
            "wakeCadence": wakeCadence, "timezone": timezone,
        ]
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { body["name"] = trimmed }
        return body
    }
}

struct Approval: Decodable, Identifiable, Hashable {
    let id: String
    let employeeId: String
    let title: String
    let situation: String
    let recommendation: String
    let reason: String
    let risk: String
    let primaryAction: String
    var status: String
}

struct Activity: Decodable, Identifiable, Hashable {
    let id: String
    let employeeId: String
    let at: String
    let title: String
    let summary: String
    let kind: String
}

struct Conversation: Decodable, Identifiable, Hashable {
    let id: String
    let employeeId: String
    let title: String
    let status: String
    let messageCount: Int
    let lastMessageAt: String?
    let createdAt: String
}

struct ConversationDetail: Decodable {
    let conversation: Conversation
    let messages: [ChatMessage]
}

struct ChatMessage: Decodable, Identifiable, Hashable {
    let id: String
    let employeeId: String
    let conversationId: String?
    let role: String
    let body: String
    let at: String

    var isUser: Bool { role == "user" || role == "principal" || role == "owner" }
}

struct WorkingStep: Decodable, Identifiable, Hashable {
    var id: String { "\(tool)-\(operation)-\(label)" }
    let tool: String
    let operation: String
    let label: String
    let status: String
    let summary: String
}

struct WorkingRun: Decodable, Hashable {
    let active: Bool
    let runId: String?
    let status: String
    let goal: String
    let phase: String
    let steps: [WorkingStep]
}

struct ConnectedTool: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let description: String
    let connected: Bool
    let read: String
    let write: String
    let send: String
    let delete: String?
    let access: String?
    let employeeId: String?
}

struct WakeJob: Decodable, Identifiable, Hashable {
    let id: String
    let employeeId: String
    let title: String
    let instruction: String
    let cadence: String
    let cadenceLabel: String
    let timezone: String
    let nextRunAt: String?
    let enabled: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, instruction, cadence, timezone, enabled, employeeId, cadenceLabel, nextRunAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? c.decode(String.self, forKey: .id)) ?? UUID().uuidString
        employeeId = (try? c.decode(String.self, forKey: .employeeId)) ?? ""
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Recurring task"
        instruction = try c.decodeIfPresent(String.self, forKey: .instruction) ?? ""
        cadence = try c.decodeIfPresent(String.self, forKey: .cadence) ?? ""
        cadenceLabel = try c.decodeIfPresent(String.self, forKey: .cadenceLabel) ?? ""
        timezone = try c.decodeIfPresent(String.self, forKey: .timezone) ?? ""
        nextRunAt = try c.decodeIfPresent(String.self, forKey: .nextRunAt)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    var scheduleDisplay: String {
        let label = cadenceLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !label.isEmpty { return label }
        return cadence.isEmpty ? "Schedule unset" : cadence
    }
}

struct LibraryDocument: Decodable, Identifiable, Hashable {
    let id: String
    let title: String
    let folder: String
    let format: String
    let employeeId: String?
    let createdAt: String
    let updatedAt: String
    let excerpt: String
    let downloads: [Download]
    let content: String?

    struct Download: Decodable, Hashable {
        let format: String
        let url: String
    }

    enum CodingKeys: String, CodingKey {
        case id, title, folder, format, excerpt, downloads, content
        case employeeId = "employee_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? "Untitled"
        folder = try c.decodeIfPresent(String.self, forKey: .folder) ?? "Documents"
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? "markdown"
        employeeId = try c.decodeIfPresent(String.self, forKey: .employeeId)
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try c.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
        excerpt = try c.decodeIfPresent(String.self, forKey: .excerpt) ?? ""
        downloads = try c.decodeIfPresent([Download].self, forKey: .downloads) ?? []
        content = try c.decodeIfPresent(String.self, forKey: .content)
    }
}

struct DocumentListing: Decodable {
    let documents: [LibraryDocument]
    let folders: [String]

    enum CodingKeys: String, CodingKey { case documents, folders }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        documents = try c.decodeIfPresent([LibraryDocument].self, forKey: .documents) ?? []
        folders = try c.decodeIfPresent([String].self, forKey: .folders) ?? []
    }
}

struct LlmModel: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let tier: String
    let note: String
}

struct LlmProvider: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let keyLabel: String
    let keyHint: String
    let allowEmptyKey: Bool
    let allowCustomModel: Bool
    let models: [LlmModel]
}

struct LlmSettings: Decodable, Hashable {
    let provider: String
    let model: String
    let baseUrl: String
    let keyConfigured: Bool
    let keyHint: String
    let fallbackModels: [String]
    /// Set by newer servers when Syph manages the model; absent on older ones.
    let managed: Bool?

    var isManaged: Bool { managed ?? false }
}

struct SettingsResult: Decodable {
    let ok: Bool
    let message: String
}

struct ConnectResult: Decodable {
    let url: String
}

struct WorkspacePayload: Decodable {
    let user: SyphUser
    let employees: [Employee]
    let approvals: [Approval]
    let activity: [Activity]
    let jobs: [WakeJob]
    let conversations: [Conversation]
    let messages: [ChatMessage]
    let accountTools: [ConnectedTool]
    let employeeTools: [ConnectedTool]

    enum CodingKeys: String, CodingKey {
        case user, employees, approvals, activity, jobs, conversations, messages, accountTools, employeeTools
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        user = try c.decode(SyphUser.self, forKey: .user)
        employees = try c.decodeIfPresent([Employee].self, forKey: .employees) ?? []
        approvals = try c.decodeIfPresent([Approval].self, forKey: .approvals) ?? []
        activity = try c.decodeIfPresent([Activity].self, forKey: .activity) ?? []
        jobs = (try? c.decodeIfPresent([WakeJob].self, forKey: .jobs)) ?? []
        conversations = try c.decodeIfPresent([Conversation].self, forKey: .conversations) ?? []
        messages = try c.decodeIfPresent([ChatMessage].self, forKey: .messages) ?? []
        accountTools = try c.decodeIfPresent([ConnectedTool].self, forKey: .accountTools) ?? []
        employeeTools = try c.decodeIfPresent([ConnectedTool].self, forKey: .employeeTools) ?? []
    }
}

struct CommandResponse: Decodable {
    let ok: Bool
    let runId: String?
}

// MARK: - Devices (computer control)

struct DeviceRecord: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let platform: String
    let model: String
    let osVersion: String
    let appVersion: String
    let controlEnabled: Bool
    let scopes: [String: String]
    let online: Bool
    let lastSeenAt: String?
}

/// A command queued by an employee for this Mac. `arguments` stay loosely typed:
/// the executor reads what each operation needs.
struct DeviceCommand: Decodable, Identifiable, Hashable {
    let id: String
    let deviceId: String?
    let employeeId: String?
    let employeeName: String
    let runId: String?
    let operation: String
    let arguments: [String: JSONValue]
    let status: String
    let summary: String
    let createdAt: String
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, deviceId, employeeId, employeeName, runId, operation, arguments, status, summary, createdAt, completedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        deviceId = try c.decodeIfPresent(String.self, forKey: .deviceId)
        employeeId = try c.decodeIfPresent(String.self, forKey: .employeeId)
        employeeName = try c.decodeIfPresent(String.self, forKey: .employeeName) ?? ""
        runId = try c.decodeIfPresent(String.self, forKey: .runId)
        operation = try c.decode(String.self, forKey: .operation)
        arguments = try c.decodeIfPresent([String: JSONValue].self, forKey: .arguments) ?? [:]
        status = try c.decodeIfPresent(String.self, forKey: .status) ?? "queued"
        summary = try c.decodeIfPresent(String.self, forKey: .summary) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        completedAt = try c.decodeIfPresent(String.self, forKey: .completedAt)
    }

    func string(_ key: String) -> String? {
        arguments[key]?.stringValue.flatMap { $0.isEmpty ? nil : $0 }
    }

    func double(_ key: String) -> Double? { arguments[key]?.doubleValue }
}

struct NextCommandEnvelope: Decodable {
    let command: DeviceCommand?
}

/// Minimal JSON value so heterogeneous arguments and results round-trip.
enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSONValue].self) { self = .array(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .null }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        case .null: try c.encodeNil()
        }
    }

    var stringValue: String? {
        switch self {
        case .string(let v): return v
        case .number(let v): return v.rounded() == v ? String(Int(v)) : String(v)
        case .bool(let v): return v ? "true" : "false"
        default: return nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let v): return v
        case .string(let v): return Double(v)
        default: return nil
        }
    }

    /// Converts to Foundation types for JSONSerialization.
    var foundation: Any {
        switch self {
        case .string(let v): return v
        case .number(let v): return v
        case .bool(let v): return v
        case .array(let v): return v.map(\.foundation)
        case .object(let v): return v.mapValues(\.foundation)
        case .null: return NSNull()
        }
    }
}

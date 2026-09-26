import AppKit
import Foundation
import Observation
import SwiftUI

/// One line in the on-device action log.
struct LocalAction: Identifiable {
    let id: String
    let employee: String
    let operation: String
    let scope: ComputerScope?
    var status: String
    var summary: String
    let startedAt: Date
    var finishedAt: Date?
    var thumbnail: NSImage?
    var detail: String
}

/// Links this Mac to the workspace and runs what employees ask of it.
///
/// Lifecycle: register (PUT /devices/{id}) → heartbeat every 25 s → long-poll
/// /commands/next. Each command is checked against the owner's local scopes,
/// asked about if the scope is ask-first, run with the overlay showing, and
/// reported back. Switching control off cancels server-side queues too.
@MainActor
@Observable
final class DeviceBridge {
    enum Link: Equatable { case idle, linking, online, offline(String) }

    private static let idKey = "syph.device.id"

    let deviceID: String
    let policy: ComputerPolicy
    let consent = ConsentCenter()
    let overlay = AgentOverlay()
    var link: Link = .idle
    var log: [LocalAction] = []
    var current: LocalAction?
    var remoteDevices: [DeviceRecord] = []

    @ObservationIgnored private let api: APIClient
    @ObservationIgnored private lazy var executor = ComputerExecutor(policy: policy)
    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var heartbeatTask: Task<Void, Never>?
    @ObservationIgnored private var runningTask: Task<Void, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?

    init(api: APIClient, policy: ComputerPolicy) {
        self.api = api
        self.policy = policy
        if let saved = UserDefaults.standard.string(forKey: Self.idKey) {
            deviceID = saved
        } else {
            let fresh = UUID().uuidString.lowercased()
            UserDefaults.standard.set(fresh, forKey: Self.idKey)
            deviceID = fresh
        }
        policy.onChange = { [weak self] in self?.scheduleSync() }
        overlay.onStop = { [weak self] in self?.emergencyStop() }
    }

    var isRunning: Bool { current != nil }

    // MARK: Lifecycle

    func start() {
        guard pollTask == nil else { return }
        link = .linking
        pollTask = Task { [weak self] in await self?.pollLoop() }
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                await self?.heartbeat()
            }
        }
    }

    func stop() {
        pollTask?.cancel(); pollTask = nil
        heartbeatTask?.cancel(); heartbeatTask = nil
        runningTask?.cancel()
        link = .idle
    }

    /// Stop button, menu bar kill switch and ⌃⌥⌘. all land here.
    func emergencyStop() {
        runningTask?.cancel()
        policy.controlEnabled = false
        if consent.current != nil { consent.decide(.deny) }
        overlay.hide(after: .zero)
        if var action = current {
            action.status = "cancelled"
            action.summary = "Stopped by you."
            action.finishedAt = Date()
            record(action)
            current = nil
        }
    }

    private func register() async throws {
        let info = ProcessInfo.processInfo
        let version = info.operatingSystemVersion
        let body: [String: Any] = [
            "name": Host.current().localizedName ?? "Mac",
            "platform": "macos",
            "model": Self.hardwareModel(),
            "osVersion": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            "appVersion": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0",
            "controlEnabled": policy.controlEnabled,
            "scopes": policy.wireScopes,
        ]
        _ = try await api.send(DeviceRecord.self, "/api/v1/devices/\(deviceID)", method: "PUT", body: body)
        await refreshDevices()
    }

    private func heartbeat() async {
        do {
            _ = try await api.send(DeviceRecord.self, "/api/v1/devices/\(deviceID)/heartbeat", method: "POST",
                                   body: ["controlEnabled": policy.controlEnabled, "scopes": policy.wireScopes])
            if link != .online { link = .online }
        } catch let error as APIError where error.statusCode == 404 {
            try? await register()
        } catch {
            link = .offline(error.localizedDescription)
        }
    }

    private func scheduleSync() {
        syncTask?.cancel()
        syncTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.heartbeat()
            await self?.refreshDevices()
        }
    }

    func refreshDevices() async {
        remoteDevices = (try? await api.send([DeviceRecord].self, "/api/v1/devices")) ?? remoteDevices
    }

    func unlink(_ device: DeviceRecord) async {
        _ = try? await api.send(EmptyResponse.self, "/api/v1/devices/\(device.id)", method: "DELETE")
        await refreshDevices()
    }

    private func pollLoop() async {
        var backoff: Double = 2
        while !Task.isCancelled {
            do {
                if link != .online {
                    try await register()
                    link = .online
                    backoff = 2
                }
                guard policy.controlEnabled else {
                    try? await Task.sleep(for: .seconds(3))
                    continue
                }
                let envelope = try await api.send(NextCommandEnvelope.self,
                                                  "/api/v1/devices/\(deviceID)/commands/next?wait=20", timeout: 40)
                backoff = 2
                if let command = envelope.command {
                    let task = Task { await self.handle(command) }
                    runningTask = task
                    await task.value
                    runningTask = nil
                }
            } catch let error as APIError where error.statusCode == 401 {
                link = .offline("Signed out")
                return
            } catch {
                if Task.isCancelled { return }
                link = .offline(error.localizedDescription)
                try? await Task.sleep(for: .seconds(backoff))
                backoff = min(backoff * 2, 30)
            }
        }
    }

    // MARK: Commands

    private func handle(_ command: DeviceCommand) async {
        let scope = ComputerScope.forOperation(command.operation)
        var action = LocalAction(id: command.id, employee: command.employeeName, operation: command.operation,
                                 scope: scope, status: "running", summary: ConsentCenter.headline(command),
                                 startedAt: Date(), detail: ConsentCenter.detail(command))
        current = action

        guard let scope else {
            await finish(&action, status: "failed", result: .fail("Unknown operation \(command.operation)."))
            return
        }
        switch policy.mode(scope) {
        case .off:
            await finish(&action, status: "denied", result: .fail("“\(scope.title)” is switched off on this Mac."))
            return
        case .ask:
            switch await consent.ask(employee: command.employeeName, scope: scope, command: command) {
            case .deny:
                await finish(&action, status: "denied", result: .fail("You declined on your Mac."))
                return
            case .always:
                policy.set(scope, .allow)
            case .once:
                break
            }
        case .allow:
            break
        }
        guard !Task.isCancelled, policy.controlEnabled else {
            await finish(&action, status: "denied", result: .fail("Computer control was switched off."))
            return
        }

        let visible = scope != .observe && scope != .clipboard
        if visible {
            overlay.show(employee: command.employeeName, activity: action.summary,
                         tint: command.employeeId.map(Palette.hue(for:)) ?? Palette.ice)
        }
        if command.operation == "notify" {
            overlay.show(employee: command.employeeName, activity: command.string("text") ?? "Heads up",
                         tint: Palette.mint)
        }
        await report(command.id, status: "running", summary: action.summary, data: [:])
        let result = await executor.run(command)
        if visible || command.operation == "notify" { overlay.hide(after: command.operation == "notify" ? .seconds(5) : .milliseconds(1400)) }
        if Task.isCancelled {
            await finish(&action, status: "failed", result: .fail("Stopped by the owner."))
            return
        }
        await finish(&action, status: result.ok ? "succeeded" : "failed", result: result)
    }

    private func finish(_ action: inout LocalAction, status: String, result: ExecutionResult) async {
        action.status = status
        action.summary = result.summary
        action.finishedAt = Date()
        if let base64 = result.data["_image"] as? String, let data = Data(base64Encoded: base64) {
            action.thumbnail = NSImage(data: data)
        }
        record(action)
        current = nil
        await report(action.id, status: status, summary: result.summary, data: result.data)
    }

    private func record(_ action: LocalAction) {
        log.insert(action, at: 0)
        if log.count > 120 { log.removeLast(log.count - 120) }
    }

    private func report(_ commandID: String, status: String, summary: String, data: [String: Any]) async {
        let safe = JSONSerialization.isValidJSONObject(data) ? data : ["note": "Result could not be encoded."]
        _ = try? await api.send(EmptyResponse.self, "/api/v1/devices/\(deviceID)/commands/\(commandID)", method: "POST",
                                body: ["status": status, "summary": String(summary.prefix(3900)), "data": safe])
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "Mac" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(cString: buffer)
    }
}

import AppKit
import Foundation

/// The result a device reports for one command.
struct ExecutionResult {
    var ok: Bool
    var summary: String
    var data: [String: Any] = [:]

    static func fail(_ summary: String) -> ExecutionResult { ExecutionResult(ok: false, summary: summary) }
}

/// Performs computer commands on this Mac. Scope and consent are checked by
/// `DeviceBridge` before anything here runs; file paths are re-checked here
/// against the shared folders on every call.
@MainActor
final class ComputerExecutor {
    private let policy: ComputerPolicy

    init(policy: ComputerPolicy) {
        self.policy = policy
    }

    func run(_ command: DeviceCommand) async -> ExecutionResult {
        do {
            switch command.operation {
            case "observe": return observe()
            case "read_screen": return try await readScreen()
            case "read_ui": return try readUI()
            case "click": return try await click(command)
            case "click_text": return try await clickText(command)
            case "press": return try press(command)
            case "type_text": return try await typeText(command)
            case "press_keys": return try await pressKeys(command)
            case "scroll": return try scroll(command)
            case "open_app": return await openApp(command)
            case "quit_app": return quitApp(command)
            case "open_url": return openURL(command)
            case "list_files": return try listFiles(command)
            case "read_file": return try readFile(command)
            case "write_file": return try writeFile(command)
            case "trash_file": return try trashFile(command)
            case "run_shell": return await runShell(command)
            case "applescript": return await appleScript(command)
            case "clipboard_read": return clipboardRead()
            case "clipboard_write": return clipboardWrite(command)
            case "notify": return .init(ok: true, summary: "Showed the notice.")
            default: return .fail("This Mac doesn’t know how to \(command.operation).")
            }
        } catch {
            return .fail(error.localizedDescription)
        }
    }

    // MARK: Seeing

    private func observe() -> ExecutionResult {
        let front = NSWorkspace.shared.frontmostApplication
        let apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap(\.localizedName)
        let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let windows: [[String: Any]] = info.compactMap { row in
            guard (row[kCGWindowLayer as String] as? Int) == 0,
                  let owner = row[kCGWindowOwnerName as String] as? String, owner != "Syph" else { return nil }
            return ["app": owner, "title": row[kCGWindowName as String] as? String ?? ""]
        }
        let screen = NSScreen.main?.frame.size ?? .zero
        let pointer = InputSynth.currentPointerLocation()
        let name = front?.localizedName ?? "nothing"
        return ExecutionResult(ok: true, summary: "\(name) is in front; \(windows.count) windows open.", data: [
            "app": name,
            "bundle_id": front?.bundleIdentifier ?? "",
            "windows": Array(windows.prefix(40)),
            "running_apps": apps,
            "screen": ["width": screen.width, "height": screen.height],
            "pointer": ["x": pointer.x.rounded(), "y": pointer.y.rounded()],
        ])
    }

    private func readScreen() async throws -> ExecutionResult {
        let reading = try await ScreenReader.read()
        let lines = reading.lines.filter { $0.confidence > 0.3 }
        let text = lines.map(\.text).joined(separator: "\n")
        var data: [String: Any] = [
            "text": text,
            "lines": lines.prefix(250).map { line in
                ["text": line.text, "x": line.frame.midX.rounded(), "y": line.frame.midY.rounded(),
                 "w": line.frame.width.rounded(), "h": line.frame.height.rounded()] as [String: Any]
            },
            "screen": ["width": reading.size.width, "height": reading.size.height],
            "app": NSWorkspace.shared.frontmostApplication?.localizedName ?? "",
        ]
        if let thumb = reading.thumbnailBase64 { data["_image"] = thumb }
        return ExecutionResult(ok: true, summary: "Read \(lines.count) lines of text on screen.", data: data)
    }

    private func readUI() throws -> ExecutionResult {
        let (app, window, elements) = try AXReader.elements()
        let rows: [[String: Any]] = elements.map { element in
            ["role": element.role.replacingOccurrences(of: "AX", with: ""), "title": element.title, "value": element.value,
             "x": element.frame.midX.rounded(), "y": element.frame.midY.rounded(),
             "w": element.frame.width.rounded(), "h": element.frame.height.rounded()]
        }
        return ExecutionResult(ok: true, summary: "Found \(rows.count) controls in \(app)\(window.isEmpty ? "" : " — \(window)").",
                               data: ["app": app, "window": window, "elements": rows])
    }

    // MARK: Acting

    private func click(_ command: DeviceCommand) async throws -> ExecutionResult {
        guard let x = command.double("x"), let y = command.double("y") else { return .fail("click needs x and y.") }
        let right = command.string("button") == "right"
        let count = Int(command.double("count") ?? 1)
        try await InputSynth.click(at: CGPoint(x: x, y: y), right: right, count: count)
        return .init(ok: true, summary: "Clicked at \(Int(x)), \(Int(y)).")
    }

    private func clickText(_ command: DeviceCommand) async throws -> ExecutionResult {
        guard let query = command.string("text") else { return .fail("click_text needs text.") }
        let reading = try await ScreenReader.read(includeThumbnail: false)
        guard let line = ScreenReader.locate(query, in: reading.lines) else {
            let sample = reading.lines.prefix(30).map(\.text).joined(separator: " · ")
            return ExecutionResult(ok: false, summary: "“\(query)” isn’t visible on screen.", data: ["visible": sample])
        }
        let point = ScreenReader.focus(of: query, in: line)
        try await InputSynth.click(at: point, count: Int(command.double("count") ?? 1))
        return ExecutionResult(ok: true, summary: "Clicked “\(line.text)”.", data: ["x": point.x.rounded(), "y": point.y.rounded()])
    }

    private func press(_ command: DeviceCommand) throws -> ExecutionResult {
        guard let title = command.string("title") ?? command.string("text") else { return .fail("press needs a title.") }
        guard let element = try AXReader.press(title) else {
            return .fail("No control titled “\(title)” in the front window. Try read_ui to see what’s there.")
        }
        return .init(ok: true, summary: "Pressed “\(element.title)”.")
    }

    private func typeText(_ command: DeviceCommand) async throws -> ExecutionResult {
        guard let text = command.string("text") else { return .fail("type_text needs text.") }
        try await InputSynth.type(text)
        return .init(ok: true, summary: "Typed \(text.count) characters into \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "the front app").")
    }

    private func pressKeys(_ command: DeviceCommand) async throws -> ExecutionResult {
        guard let keys = command.string("keys") else { return .fail("press_keys needs keys, like cmd+s.") }
        try await InputSynth.press(keys)
        return .init(ok: true, summary: "Pressed \(keys).")
    }

    private func scroll(_ command: DeviceCommand) throws -> ExecutionResult {
        let direction = command.string("direction") ?? "down"
        try InputSynth.scroll(direction: direction, amount: Int(command.double("amount") ?? 5))
        return .init(ok: true, summary: "Scrolled \(direction).")
    }

    // MARK: Apps

    private func openApp(_ command: DeviceCommand) async -> ExecutionResult {
        guard let name = command.string("app") else { return .fail("open_app needs an app name.") }
        guard let url = Self.applicationURL(name) else { return .fail("Couldn’t find an app called “\(name)”.") }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        do {
            let app = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            try? await Task.sleep(for: .milliseconds(600))
            return .init(ok: true, summary: "Opened \(app.localizedName ?? name).")
        } catch {
            return .fail("Couldn’t open \(name): \(error.localizedDescription)")
        }
    }

    private func quitApp(_ command: DeviceCommand) -> ExecutionResult {
        guard let name = command.string("app")?.lowercased() else { return .fail("quit_app needs an app name.") }
        let matches = NSWorkspace.shared.runningApplications.filter {
            $0.localizedName?.lowercased() == name || $0.bundleIdentifier?.lowercased() == name
        }
        guard !matches.isEmpty else { return .fail("\(name) isn’t running.") }
        guard !matches.contains(where: { $0.bundleIdentifier == Bundle.main.bundleIdentifier }) else {
            return .fail("Syph won’t quit itself.")
        }
        matches.forEach { $0.terminate() }
        return .init(ok: true, summary: "Asked \(matches.first?.localizedName ?? name) to quit.")
    }

    private func openURL(_ command: DeviceCommand) -> ExecutionResult {
        guard let raw = command.string("url") else { return .fail("open_url needs a url.") }
        let fixed = raw.contains("://") ? raw : "https://\(raw)"
        guard let url = URL(string: fixed), let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto", "tel", "facetime", "maps"].contains(scheme) else {
            return .fail("Only web, mail and similar links can be opened.")
        }
        NSWorkspace.shared.open(url)
        return .init(ok: true, summary: "Opened \(url.host ?? fixed).")
    }

    static func applicationURL(_ name: String) -> URL? {
        if name.contains("."), let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) { return url }
        let wanted = name.lowercased().replacingOccurrences(of: ".app", with: "")
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                     "/Applications/Utilities", "\(home)/Applications"]
        for root in roots {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            if let hit = items.first(where: { $0.lowercased() == "\(wanted).app" }) {
                return URL(fileURLWithPath: root).appendingPathComponent(hit)
            }
        }
        for root in roots {
            guard let items = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            if let hit = items.first(where: { $0.lowercased().hasSuffix(".app") && $0.lowercased().contains(wanted) }) {
                return URL(fileURLWithPath: root).appendingPathComponent(hit)
            }
        }
        return nil
    }

    // MARK: Files

    private func listFiles(_ command: DeviceCommand) throws -> ExecutionResult {
        guard let raw = command.string("path") else {
            let folders = policy.sharedFolders.map { ["name": $0.lastPathComponent, "path": $0.path, "kind": "folder"] }
            return ExecutionResult(ok: true, summary: "\(folders.count) shared folder\(folders.count == 1 ? "" : "s").",
                                   data: ["entries": folders])
        }
        guard let url = policy.resolveShared(raw) else { return .fail(outsideShared(raw)) }
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        let items = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        let entries: [[String: Any]] = items.prefix(300).map { item in
            let values = try? item.resourceValues(forKeys: Set(keys))
            return [
                "name": item.lastPathComponent,
                "path": item.path,
                "kind": values?.isDirectory == true ? "folder" : "file",
                "size": values?.fileSize ?? 0,
                "modified": values?.contentModificationDate.map { ISO8601DateFormatter().string(from: $0) } ?? "",
            ]
        }
        return ExecutionResult(ok: true, summary: "\(entries.count) items in \(url.lastPathComponent).", data: ["entries": entries, "path": url.path])
    }

    private func readFile(_ command: DeviceCommand) throws -> ExecutionResult {
        guard let raw = command.string("path") else { return .fail("read_file needs a path.") }
        guard let url = policy.resolveShared(raw) else { return .fail(outsideShared(raw)) }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard let text = String(data: data.prefix(400_000), encoding: .utf8) else {
            return .fail("\(url.lastPathComponent) isn’t a text file.")
        }
        return ExecutionResult(ok: true, summary: "Read \(url.lastPathComponent) (\(data.count) bytes).",
                               data: ["content": text, "path": url.path, "bytes": data.count])
    }

    private func writeFile(_ command: DeviceCommand) throws -> ExecutionResult {
        guard let raw = command.string("path") else { return .fail("write_file needs a path.") }
        guard let url = policy.resolveShared(raw) else { return .fail(outsideShared(raw)) }
        let content = command.string("content") ?? ""
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try content.write(to: url, atomically: true, encoding: .utf8)
        return ExecutionResult(ok: true, summary: "Saved \(url.lastPathComponent).", data: ["path": url.path, "bytes": content.utf8.count])
    }

    private func trashFile(_ command: DeviceCommand) throws -> ExecutionResult {
        guard let raw = command.string("path") else { return .fail("trash_file needs a path.") }
        guard let url = policy.resolveShared(raw) else { return .fail(outsideShared(raw)) }
        guard !policy.sharedFolders.contains(where: { $0.standardizedFileURL.path == url.path }) else {
            return .fail("A shared folder itself can’t be trashed.")
        }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        return .init(ok: true, summary: "Moved \(url.lastPathComponent) to the Trash.")
    }

    private func outsideShared(_ path: String) -> String {
        "“\(path)” is outside the folders the owner shared (\(policy.sharedFolders.map(\.path).joined(separator: ", ")))."
    }

    // MARK: Shell & AppleScript

    private func runShell(_ command: DeviceCommand) async -> ExecutionResult {
        guard let line = command.string("command") else { return .fail("run_shell needs a command.") }
        let cwd = policy.sharedFolders.first ?? FileManager.default.homeDirectoryForCurrentUser
        let output = await ProcessRunner.run("/bin/zsh", ["-lc", line], cwd: cwd, timeout: 120)
        return shaped(output, label: "Command")
    }

    private func appleScript(_ command: DeviceCommand) async -> ExecutionResult {
        guard let script = command.string("script") else { return .fail("applescript needs a script.") }
        let output = await ProcessRunner.run("/usr/bin/osascript", ["-e", script], cwd: nil, timeout: 80)
        return shaped(output, label: "Script")
    }

    private func shaped(_ output: ProcessRunner.Output, label: String) -> ExecutionResult {
        let data: [String: Any] = ["stdout": output.stdout, "stderr": output.stderr, "exit_code": output.status]
        if output.timedOut { return ExecutionResult(ok: false, summary: "\(label) timed out.", data: data) }
        if output.status != 0 {
            let reason = output.stderr.split(separator: "\n").last.map(String.init) ?? "exit \(output.status)"
            return ExecutionResult(ok: false, summary: "\(label) failed: \(reason)", data: data)
        }
        let first = output.stdout.split(separator: "\n").first.map(String.init) ?? ""
        return ExecutionResult(ok: true, summary: first.isEmpty ? "\(label) finished." : "\(label) finished: \(first.prefix(120))", data: data)
    }

    // MARK: Clipboard

    private func clipboardRead() -> ExecutionResult {
        let text = NSPasteboard.general.string(forType: .string) ?? ""
        return ExecutionResult(ok: true, summary: text.isEmpty ? "The clipboard has no text." : "Read \(text.count) characters from the clipboard.",
                               data: ["content": String(text.prefix(20_000))])
    }

    private func clipboardWrite(_ command: DeviceCommand) -> ExecutionResult {
        let text = command.string("text") ?? command.string("content") ?? ""
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        return .init(ok: true, summary: "Copied \(text.count) characters to the clipboard.")
    }
}

/// Written by one reader thread, read after the group joins.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

/// Runs a process off the main thread with a timeout, draining both pipes.
enum ProcessRunner {
    struct Output {
        var stdout: String
        var stderr: String
        var status: Int32
        var timedOut: Bool
    }

    static func run(_ launchPath: String, _ arguments: [String], cwd: URL?, timeout: TimeInterval) async -> Output {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: launchPath)
                process.arguments = arguments
                if let cwd { process.currentDirectoryURL = cwd }
                let out = Pipe(), err = Pipe()
                process.standardOutput = out
                process.standardError = err
                process.standardInput = FileHandle.nullDevice
                let outBox = DataBox(), errBox = DataBox()
                let group = DispatchGroup()
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Output(stdout: "", stderr: error.localizedDescription, status: -1, timedOut: false))
                    return
                }
                group.enter()
                DispatchQueue.global().async { outBox.data = out.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                group.enter()
                DispatchQueue.global().async { errBox.data = err.fileHandleForReading.readDataToEndOfFile(); group.leave() }
                var timedOut = false
                if group.wait(timeout: .now() + timeout) == .timedOut {
                    timedOut = true
                    process.terminate()
                    _ = group.wait(timeout: .now() + 2)
                }
                process.waitUntilExit()
                let clip: (Data) -> String = { data in
                    let text = String(decoding: data.prefix(60_000), as: UTF8.self)
                    return data.count > 60_000 ? text + "\n… (truncated)" : text
                }
                continuation.resume(returning: Output(stdout: clip(outBox.data), stderr: clip(errBox.data),
                                                      status: process.terminationStatus, timedOut: timedOut))
            }
        }
    }
}

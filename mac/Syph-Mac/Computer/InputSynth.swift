import AppKit
import ApplicationServices
import CoreGraphics

/// Synthesised mouse and keyboard events. Requires Accessibility permission.
enum InputSynth {
    enum Failure: LocalizedError {
        case permission, badKeys(String)
        var errorDescription: String? {
            switch self {
            case .permission: return "Accessibility permission is off for Syph. Turn it on in System Settings → Privacy & Security."
            case .badKeys(let keys): return "“\(keys)” isn’t a shortcut this Mac understands."
            }
        }
    }

    static func ensureTrusted() throws {
        guard AXIsProcessTrusted() else { throw Failure.permission }
    }

    private static var source: CGEventSource? { CGEventSource(stateID: .hidSystemState) }

    static func move(to point: CGPoint) {
        CGEvent(mouseEventSource: source, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    /// Glides the pointer so the owner can follow what is happening.
    static func glide(to point: CGPoint, duration: TimeInterval = 0.28) async {
        let start = currentPointerLocation()
        let steps = 14
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let eased = t < 0.5 ? 2 * t * t : 1 - pow(-2 * t + 2, 2) / 2
            move(to: CGPoint(x: start.x + (point.x - start.x) * eased, y: start.y + (point.y - start.y) * eased))
            try? await Task.sleep(for: .milliseconds(Int(duration * 1000) / steps))
        }
    }

    static func click(at point: CGPoint, right: Bool = false, count: Int = 1) async throws {
        try ensureTrusted()
        await glide(to: point)
        let down: CGEventType = right ? .rightMouseDown : .leftMouseDown
        let up: CGEventType = right ? .rightMouseUp : .leftMouseUp
        let button: CGMouseButton = right ? .right : .left
        for clickIndex in 1...max(1, min(count, 3)) {
            for type in [down, up] {
                let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button)
                event?.setIntegerValueField(.mouseEventClickState, value: Int64(clickIndex))
                event?.post(tap: .cghidEventTap)
                try? await Task.sleep(for: .milliseconds(18))
            }
        }
    }

    static func type(_ text: String) async throws {
        try ensureTrusted()
        let units = Array(text.utf16)
        var index = 0
        while index < units.count {
            let chunk = Array(units[index..<min(index + 16, units.count)])
            for keyDown in [true, false] {
                let event = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: keyDown)
                chunk.withUnsafeBufferPointer { buffer in
                    event?.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                }
                event?.post(tap: .cghidEventTap)
            }
            index += 16
            try? await Task.sleep(for: .milliseconds(12))
        }
    }

    static func press(_ combo: String) async throws {
        try ensureTrusted()
        let parts = combo.lowercased().replacingOccurrences(of: " ", with: "")
            .split(separator: "+").map(String.init)
        var flags: CGEventFlags = []
        var keyCode: CGKeyCode?
        for part in parts {
            switch part {
            case "cmd", "command", "⌘", "meta": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default: keyCode = Self.keyCodes[part]
            }
        }
        guard let keyCode else { throw Failure.badKeys(combo) }
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: keyDown)
            event?.flags = flags
            event?.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    static func scroll(direction: String, amount: Int) throws {
        try ensureTrusted()
        let lines = Int32(max(1, min(amount, 50)))
        var dy: Int32 = 0, dx: Int32 = 0
        switch direction.lowercased() {
        case "up": dy = lines
        case "left": dx = lines
        case "right": dx = -lines
        default: dy = -lines
        }
        CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    /// Pointer location in top-left global coordinates.
    static func currentPointerLocation() -> CGPoint {
        CGEvent(source: nil)?.location ?? .zero
    }

    static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11,
        "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21,
        "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "minus": 27, "8": 28, "0": 29, "]": 30, "o": 31,
        "u": 32, "[": 33, "i": 34, "p": 35, "return": 36, "enter": 36, "l": 37, "j": 38, "'": 39,
        "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47, "tab": 48,
        "space": 49, "`": 50, "delete": 51, "backspace": 51, "escape": 53, "esc": 53,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97, "f7": 98, "f8": 100,
        "f9": 101, "f10": 109, "f11": 103, "f12": 111, "home": 115, "pageup": 116,
        "forwarddelete": 117, "end": 119, "pagedown": 121, "left": 123, "right": 124,
        "down": 125, "up": 126,
    ]
}

/// Reads and presses controls through the Accessibility API.
enum AXReader {
    struct Element {
        let role: String
        let title: String
        let value: String
        let frame: CGRect
        let ref: AXUIElement
    }

    static func frontmostApplication() -> NSRunningApplication? {
        NSWorkspace.shared.frontmostApplication
    }

    static func elements(limit: Int = 220) throws -> (app: String, window: String, elements: [Element]) {
        try InputSynth.ensureTrusted()
        guard let app = frontmostApplication() else { return ("", "", []) }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        var window = root
        if let focused = attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() {
            window = focused as! AXUIElement
        }
        var found: [Element] = []
        walk(window, depth: 0, into: &found, limit: limit)
        let title = string(window, kAXTitleAttribute)
        return (app.localizedName ?? "", title, found)
    }

    /// Presses the first control whose title, description or value matches.
    static func press(_ query: String) throws -> Element? {
        let needle = query.lowercased()
        let (_, _, elements) = try elements(limit: 600)
        let actionable = elements.filter { ["AXButton", "AXMenuItem", "AXCheckBox", "AXRadioButton", "AXLink", "AXPopUpButton", "AXMenuBarItem", "AXTab", "AXCell", "AXStaticText"].contains($0.role) }
        let candidate = actionable.first { $0.title.lowercased() == needle }
            ?? actionable.first { $0.title.lowercased().contains(needle) }
        guard let candidate else { return nil }
        AXUIElementPerformAction(candidate.ref, kAXPressAction as CFString)
        return candidate
    }

    private static func walk(_ element: AXUIElement, depth: Int, into found: inout [Element], limit: Int) {
        guard depth < 12, found.count < limit else { return }
        let role = string(element, kAXRoleAttribute)
        let title = [string(element, kAXTitleAttribute), string(element, kAXDescriptionAttribute)]
            .first { !$0.isEmpty } ?? ""
        let value = string(element, kAXValueAttribute)
        let interesting = !title.isEmpty || (!value.isEmpty && role != "AXStaticText") || role == "AXTextField" || role == "AXTextArea"
        if interesting, let frame = frame(element) {
            found.append(Element(role: role, title: title, value: String(value.prefix(200)), frame: frame, ref: element))
        }
        guard let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for child in children {
            walk(child, depth: depth + 1, into: &found, limit: limit)
            if found.count >= limit { return }
        }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    private static func string(_ element: AXUIElement, _ name: String) -> String {
        if let s = attribute(element, name) as? String { return s }
        if let n = attribute(element, name) as? NSNumber { return n.stringValue }
        return ""
    }

    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let posRef = attribute(element, kAXPositionAttribute), let sizeRef = attribute(element, kAXSizeAttribute),
              CFGetTypeID(posRef) == AXValueGetTypeID(), CFGetTypeID(sizeRef) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(posRef as! AXValue, .cgPoint, &point)
        AXValueGetValue(sizeRef as! AXValue, .cgSize, &size)
        guard size.width > 1, size.height > 1 else { return nil }
        return CGRect(origin: point, size: size)
    }
}

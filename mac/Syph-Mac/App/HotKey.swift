import AppKit
import Carbon.HIToolbox

/// System-wide shortcuts via Carbon — no Accessibility permission needed.
final class HotKeyCenter {
    static let shared = HotKeyCenter()

    private var handlers: [UInt32: () -> Void] = [:]
    private var refs: [EventHotKeyRef] = []
    private var installed = false

    /// ⌥Space summons the command bar.
    static let commandBar = (key: UInt32(kVK_Space), modifiers: UInt32(optionKey))
    /// ⌥⇧Space opens or closes the desktop widget's chat.
    static let widget = (key: UInt32(kVK_Space), modifiers: UInt32(optionKey | shiftKey))
    /// ⌃⌥⌘. stops whatever an employee is doing on this Mac.
    static let killSwitch = (key: UInt32(kVK_ANSI_Period), modifiers: UInt32(controlKey | optionKey | cmdKey))

    func register(key: UInt32, modifiers: UInt32, handler: @escaping () -> Void) {
        installIfNeeded()
        let id = UInt32(handlers.count + 1)
        handlers[id] = handler
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: OSType(0x53595048), id: id) // 'SYPH'
        if RegisterEventHotKey(key, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
            refs.append(ref)
        }
    }

    private func installIfNeeded() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let id = hotKeyID.id
            DispatchQueue.main.async { HotKeyCenter.shared.handlers[id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

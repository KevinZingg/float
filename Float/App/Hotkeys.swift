import Carbon.HIToolbox

struct Hotkey {
    let keyCode: UInt32
    let modifiers: UInt32
}

/// System-wide shortcuts via Carbon `RegisterEventHotKey` (no accessibility permission needed).
@MainActor
enum Hotkeys {
    private static var actions: [UInt32: () -> Void] = [:]
    private static var nextID: UInt32 = 1
    private static var installed = false

    /// Returns false if the combo is already taken by another app.
    @discardableResult
    static func register(_ hotkey: Hotkey, action: @escaping () -> Void) -> Bool {
        installHandler()
        let id = nextID
        nextID += 1
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            hotkey.keyCode, hotkey.modifiers, EventHotKeyID(signature: OSType(0x464C_5454), id: id),
            GetApplicationEventTarget(), 0, &ref)
        guard status == noErr else { return false }
        actions[id] = action
        return true
    }

    private static func installHandler() {
        guard !installed else { return }
        installed = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var id = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &id)
            // Carbon delivers hotkey events on the main thread.
            MainActor.assumeIsolated { Hotkeys.actions[id.id]?() }
            return noErr
        }, 1, &spec, nil, nil)
    }
}

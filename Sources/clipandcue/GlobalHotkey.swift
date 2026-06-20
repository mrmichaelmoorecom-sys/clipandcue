import AppKit
import Carbon.HIToolbox

/// Registers a single user-configurable global hotkey via Carbon and fires
/// `onTrigger` when it's pressed. Re-register at any time with `register(keyCode:modifiers:)`
/// — the event handler is installed once and reused.
final class GlobalHotkey {
    var onTrigger: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType(0x434C4350), id: 1) // 'CLCP'

    /// (Re)bind the hotkey to a key code + Carbon modifier mask. Safe to call
    /// repeatedly — it tears down any previous registration first.
    func register(keyCode: UInt32, modifiers: UInt32) {
        installHandlerIfNeeded()
        unregisterKey()
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    func unregister() {
        unregisterKey()
        if let handlerRef { RemoveEventHandler(handlerRef) }
        handlerRef = nil
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        let callback: EventHandlerUPP = { _, _, userData in
            guard let userData else { return noErr }
            let me = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            me.onTrigger?()
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), callback, 1, &eventType,
                            Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
    }

    private func unregisterKey() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
    }

    deinit { unregister() }
}

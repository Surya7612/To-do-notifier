import AppKit
import Carbon.HIToolbox

/// Carbon hot key registration. Unlike an NSEvent global monitor this needs no
/// Accessibility permission, which keeps first-run friction low.
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    /// ⌥⌘Space
    nonisolated static let defaultKeyCode = UInt32(kVK_Space)
    nonisolated static let defaultModifiers = UInt32(optionKey | cmdKey)
    nonisolated static let defaultDisplayName = "⌥⌘Space"

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private init() {}

    func register(keyCode: UInt32 = defaultKeyCode,
                  modifiers: UInt32 = defaultModifiers,
                  action: @escaping () -> Void) {
        unregister()
        hotkeyAction = action

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler, 1, &spec, nil, &eventHandler)

        let id = EventHotKeyID(signature: hotkeySignature, id: hotkeyIdentifier)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &ref)
        if status == noErr {
            hotKeyRef = ref
        } else {
            NSLog("[GlobalHotkey] registration failed: \(status)")
        }
    }

    func unregister() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
        hotkeyAction = nil
    }
}

private nonisolated let hotkeySignature = OSType(0x54444348) // 'TDCH'
private nonisolated let hotkeyIdentifier: UInt32 = 1

/// The Carbon callback is a C function pointer and cannot capture context.
private nonisolated(unsafe) var hotkeyAction: (() -> Void)?

private nonisolated func hotkeyEventHandler(_ handler: EventHandlerCallRef?,
                                            _ event: EventRef?,
                                            _ context: UnsafeMutableRawPointer?) -> OSStatus {
    var id = EventHotKeyID()
    let status = GetEventParameter(event,
                                   EventParamName(kEventParamDirectObject),
                                   EventParamType(typeEventHotKeyID),
                                   nil,
                                   MemoryLayout<EventHotKeyID>.size,
                                   nil,
                                   &id)
    guard status == noErr, id.id == hotkeyIdentifier else { return noErr }
    DispatchQueue.main.async { hotkeyAction?() }
    return noErr
}

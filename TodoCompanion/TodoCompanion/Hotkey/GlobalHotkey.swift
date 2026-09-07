import AppKit
import Carbon.HIToolbox

/// Carbon hot key registration. Unlike an NSEvent global monitor this needs no
/// Accessibility permission, which keeps first-run friction low.
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    /// True when the OS refused the combo outright. Note this stays false for
    /// system-reserved combos, which register "successfully" but never fire.
    private(set) var didFailToRegister = false
    private(set) var current: HotkeyChoice = .fallback

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var storedAction: (() -> Void)?

    private init() {}

    /// Registers `choice`. Pass `action` on first call; later calls reuse it so
    /// changing the shortcut in Settings does not need the callback again.
    func activate(_ choice: HotkeyChoice, action: (() -> Void)? = nil) {
        if let action { storedAction = action }

        releaseRegistration()
        current = choice
        hotkeyAction = storedAction

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler, 1, &spec, nil, &eventHandler)

        let id = EventHotKeyID(signature: hotkeySignature, id: hotkeyIdentifier)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(choice.keyCode,
                                         choice.modifiers,
                                         id,
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr {
            hotKeyRef = ref
            didFailToRegister = false
        } else {
            didFailToRegister = true
            NSLog("[GlobalHotkey] \(choice.displayName) rejected with status \(status)")
        }
    }

    func unregister() {
        releaseRegistration()
        storedAction = nil
        hotkeyAction = nil
    }

    private func releaseRegistration() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
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

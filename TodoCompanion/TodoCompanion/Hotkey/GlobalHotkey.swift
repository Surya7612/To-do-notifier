import AppKit
import Carbon.HIToolbox

/// Carbon hot key registration. Unlike an NSEvent global monitor this needs no
/// Accessibility permission, which keeps first-run friction low.
@MainActor
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    /// What a registered combo does. Carried in the Carbon hot key's id, which
    /// is the only thing the C callback gets to see.
    enum Role: UInt32, CaseIterable {
        case summon = 1
        case talk = 2
    }

    /// True when the OS refused a combo outright. Note this stays false for
    /// system-reserved combos, which register "successfully" but never fire.
    private(set) var didFailToRegister = false
    private(set) var current: HotkeyChoice = .fallback

    private var registrations: [Role: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var storedActions: [Role: () -> Void] = [:]

    /// First half of a talk double-press, waiting for the second.
    private var talkFirstPressAt: ContinuousClock.Instant?

    /// How close together two presses of the talk shortcut must be.
    ///
    /// Long enough to hit deliberately, short enough that two unrelated
    /// presses a second apart do not summon the microphone by accident.
    private static let talkDoublePressWindow: Duration = .milliseconds(700)

    private init() {}

    /// Registers `choice` for `role`. Pass `action` on first call; later calls
    /// reuse it, so changing the shortcut in Settings does not need it again.
    ///
    /// A nil `choice` unregisters the role, which is how the talk shortcut is
    /// switched off — the summon one has no such state, since an app with no
    /// way to summon it is not a lesser configuration, it is a broken one.
    ///
    /// The talk role requires two presses inside `talkDoublePressWindow`. A
    /// single press of modifiers alone cannot be registered at all — Carbon
    /// needs a real key — and a double-tap of ⌥⌘ with no letter would need a
    /// `CGEvent` tap and the Accessibility permission this app declines to
    /// ask for. Two presses of the chosen combo is the nearest thing that
    /// still opens the microphone directly.
    func activate(_ choice: HotkeyChoice?, for role: Role = .summon, action: (() -> Void)? = nil) {
        if let action { storedActions[role] = action }
        if role == .summon, let choice { current = choice }
        if role == .talk { talkFirstPressAt = nil }

        release(role)
        installHandlerIfNeeded()

        switch role {
        case .summon:
            hotkeyActions[role.rawValue] = storedActions[role]
        case .talk:
            hotkeyActions[role.rawValue] = { [weak self] in
                Task { @MainActor in self?.handleTalkPress() }
            }
        }

        guard let choice else { return }

        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(choice.keyCode,
                                         choice.modifiers,
                                         EventHotKeyID(signature: hotkeySignature, id: role.rawValue),
                                         GetApplicationEventTarget(),
                                         0,
                                         &ref)
        if status == noErr {
            registrations[role] = ref
            if role == .summon { didFailToRegister = false }
        } else {
            if role == .summon { didFailToRegister = true }
            NSLog("[GlobalHotkey] \(choice.displayName) rejected with status \(status)")
        }
    }

    /// Completes a talk double-press, or starts waiting for one.
    private func handleTalkPress() {
        let now = ContinuousClock.now
        if let first = talkFirstPressAt, first.duration(to: now) <= Self.talkDoublePressWindow {
            talkFirstPressAt = nil
            storedActions[.talk]?()
        } else {
            talkFirstPressAt = now
        }
    }

    func unregister() {
        for role in Role.allCases { release(role) }
        storedActions = [:]
        hotkeyActions = [:]
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    /// One handler for every role. Installing it per registration stacked a
    /// second handler on the same target, so one press was delivered twice.
    private func installHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotkeyEventHandler, 1, &spec, nil, &eventHandler)
    }

    private func release(_ role: Role) {
        if let ref = registrations.removeValue(forKey: role) {
            UnregisterEventHotKey(ref)
        }
    }
}

private nonisolated let hotkeySignature = OSType(0x54444348) // 'TDCH'

/// The Carbon callback is a C function pointer and cannot capture context.
private nonisolated(unsafe) var hotkeyActions: [UInt32: () -> Void] = [:]

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
    guard status == noErr, id.signature == hotkeySignature else { return noErr }
    let action = hotkeyActions[id.id]
    DispatchQueue.main.async { action?() }
    return noErr
}

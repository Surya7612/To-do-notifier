import Carbon.HIToolbox
import Foundation

/// A summon shortcut the user can pick from.
///
/// Combos are deliberately limited to ones macOS does not reserve. Anything the
/// system claims — `⌘Space` for Spotlight, `⌥⌘Space` for the Finder search
/// window, `⌃⌘Space` for the Character Viewer — is swallowed before a Carbon
/// hot key ever sees it, and `RegisterEventHotKey` still reports success, so the
/// shortcut just silently does nothing.
struct HotkeyChoice: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let keyCode: UInt32
    let modifiers: UInt32

    nonisolated static let all: [HotkeyChoice] = [
        HotkeyChoice(id: "ctrl-opt-space",
                     displayName: "⌃⌥Space",
                     keyCode: UInt32(kVK_Space),
                     modifiers: UInt32(controlKey | optionKey)),
        HotkeyChoice(id: "ctrl-opt-cmd-space",
                     displayName: "⌃⌥⌘Space",
                     keyCode: UInt32(kVK_Space),
                     modifiers: UInt32(controlKey | optionKey | cmdKey)),
        HotkeyChoice(id: "opt-cmd-j",
                     displayName: "⌥⌘J",
                     keyCode: UInt32(kVK_ANSI_J),
                     modifiers: UInt32(optionKey | cmdKey)),
        HotkeyChoice(id: "opt-cmd-k",
                     displayName: "⌥⌘K",
                     keyCode: UInt32(kVK_ANSI_K),
                     modifiers: UInt32(optionKey | cmdKey)),
        HotkeyChoice(id: "ctrl-opt-c",
                     displayName: "⌃⌥C",
                     keyCode: UInt32(kVK_ANSI_C),
                     modifiers: UInt32(controlKey | optionKey)),
        HotkeyChoice(id: "ctrl-opt-q",
                     displayName: "⌃⌥Q",
                     keyCode: UInt32(kVK_ANSI_Q),
                     modifiers: UInt32(controlKey | optionKey)),
        HotkeyChoice(id: "opt-cmd-q",
                     displayName: "⌥⌘Q",
                     keyCode: UInt32(kVK_ANSI_Q),
                     modifiers: UInt32(optionKey | cmdKey)),
    ]

    nonisolated static let fallback = all[0]

    /// The default for "summon and start listening".
    ///
    /// A combo cannot be built from Tab and a letter, however natural that
    /// feels to type: `RegisterEventHotKey` takes a key code plus a mask of
    /// Command, Shift, Option and Control, and Tab is an ordinary key rather
    /// than a modifier. Treating it as one needs a `CGEvent` tap, which needs
    /// the Accessibility permission this app declines to require. Double-tapping
    /// ⌥⌘ with no letter has the same problem. `⌥⌘Q` pressed twice is the
    /// nearest thing that is still one motion of the left hand and still opens
    /// the microphone directly — see `GlobalHotkey`'s talk double-press window.
    nonisolated static let talkFallback = named("opt-cmd-q")

    nonisolated static func named(_ id: String?) -> HotkeyChoice {
        all.first { $0.id == id } ?? fallback
    }

    /// Like `named`, but "off" is a real answer. The talk shortcut is allowed
    /// not to exist; the summon one is not.
    nonisolated static func optional(_ id: String?) -> HotkeyChoice? {
        guard let id, id != offIdentifier else { return nil }
        return all.first { $0.id == id }
    }

    nonisolated static let offIdentifier = "off"
}

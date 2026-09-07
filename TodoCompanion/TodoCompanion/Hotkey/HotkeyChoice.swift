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
    ]

    nonisolated static let fallback = all[0]

    nonisolated static func named(_ id: String?) -> HotkeyChoice {
        all.first { $0.id == id } ?? fallback
    }
}

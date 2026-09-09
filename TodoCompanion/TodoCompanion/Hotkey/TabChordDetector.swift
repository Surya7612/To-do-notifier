import Carbon.HIToolbox
import Foundation

/// Tracks whether Tab is held, and whether a Q press completes Tab+Q.
///
/// Pure so the chord can be tested without a live event tap. Key repeats are
/// ignored: holding Q with Tab down must not summon Max once per repeat.
nonisolated struct TabChordDetector: Equatable, Sendable {
    var tabIsDown = false

    /// - Returns: `true` when this key-down should fire the Tab+Q action.
    mutating func keyDown(code: Int64, isRepeat: Bool) -> Bool {
        if code == Int64(kVK_Tab) {
            tabIsDown = true
            return false
        }
        guard code == Int64(kVK_ANSI_Q), tabIsDown, !isRepeat else { return false }
        return true
    }

    mutating func keyUp(code: Int64) {
        if code == Int64(kVK_Tab) {
            tabIsDown = false
        }
    }
}

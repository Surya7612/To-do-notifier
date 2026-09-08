import AppKit
import Foundation

/// Presents open panels on behalf of a menu bar app.
///
/// Exists because `NSOpenPanel.runModal()` does not work from an `LSUIElement`
/// app as written. Such an app has no Dock presence and is never a normal
/// foreground application, so macOS declines to give it the focus a modal file
/// dialog needs: the panel either never appears or is dismissed the instant it
/// does, and `runModal()` returns `.cancel` without the user seeing anything.
/// Nothing logs, nothing throws, and the button looks broken.
///
/// Becoming a regular application for the duration of the panel is what fixes
/// it. The cost is a Dock icon visible while the dialog is open, which is a
/// worse look than this app otherwise keeps but is strictly better than a
/// control that does nothing. The policy is restored afterwards.
@MainActor
enum FilePicker {
    /// - Parameter configure: applied to the panel before it is shown.
    /// - Returns: what the user chose, or nil if they cancelled.
    static func choose(_ configure: (NSOpenPanel) -> Void) -> URL? {
        let panel = NSOpenPanel()
        configure(panel)

        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        defer {
            if previousPolicy != .regular {
                NSApp.setActivationPolicy(previousPolicy)
            }
        }

        NSApp.activate(ignoringOtherApps: true)

        // Above the Settings window it was opened from, which is an ordinary
        // window and would otherwise be allowed to cover it.
        panel.level = .modalPanel

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }
}

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
///
/// When a normal window is already open (Settings, Library), the panel is
/// presented as a **sheet** on that window. A free-floating open panel from an
/// accessory app often lands *behind* the Settings window that opened it — the
/// Choose folder button then looks dead even though FilePicker ran.
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

        if let host = hostWindow() {
            host.makeKeyAndOrderFront(nil)
            return chooseAsSheet(panel, on: host)
        }

        panel.level = .modalPanel
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return url
    }

    /// A visible, activating window that can host a sheet — never the companion
    /// panel, which is non-activating and would swallow the dialog.
    private static func hostWindow() -> NSWindow? {
        let candidates = NSApp.windows.filter { window in
            guard window.isVisible, !(window is NSPanel) else { return false }
            // Preference / Settings windows are ordinary NSWindows; the floating
            // companion panel is an NSPanel and must not host the sheet.
            return true
        }

        if let key = candidates.first(where: \.isKeyWindow) { return key }
        if let main = candidates.first(where: \.isMainWindow) { return main }
        return candidates.first
    }

    /// Runs the open panel as a sheet and blocks until it closes, so callers can
    /// keep a synchronous `URL?` API.
    private static func chooseAsSheet(_ panel: NSOpenPanel, on window: NSWindow) -> URL? {
        var picked: URL?
        panel.beginSheetModal(for: window) { response in
            if response == .OK {
                picked = panel.url
            }
            NSApp.stopModal()
        }
        NSApp.runModal(for: window)
        return picked
    }
}

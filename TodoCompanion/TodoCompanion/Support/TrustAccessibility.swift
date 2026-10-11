import ApplicationServices
import AppKit
import Foundation

/// Whether this process may use Accessibility APIs and a CGEvent tap.
///
/// Opt-in, never required. Carbon hotkeys and OCR pointing work without it.
/// When the user enables the extras in Settings *and* macOS trusts the process,
/// Tab+Q and Show me / Guided Teach pointer warps become available.
@MainActor
enum TrustAccessibility {
    /// Posted when the Settings toggle changes, so the event tap can install
    /// or tear down without polling.
    static let extrasChangedNotification = Notification.Name("TrustAccessibility.extrasChanged")

    /// Deep links that open Privacy & Security → Accessibility.
    ///
    /// Ordered for macOS 27 first: the Privacy Security extension exports a
    /// `privacy-accessibility` type, and System Settings also claims
    /// `settings-navigation:`. The older `?Privacy_Accessibility` query form
    /// still works on many builds but is not the one that consistently lands
    /// on the *list* of apps — opening the wrong pane is why Teach looked like
    /// it never asked for Accessibility at all.
    nonisolated static let accessibilitySettingsURLCandidates: [String] = [
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension.privacy-accessibility",
        "settings-navigation:com.apple.settings.PrivacySecurity.extension.privacy-accessibility",
        "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
    ]

    /// Whether macOS currently trusts this process for Accessibility.
    static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// User wants the extras, and the grant is in place.
    static var extrasAreActive: Bool {
        AppSettings.accessibilityExtrasEnabled && isTrusted
    }

    /// Asks macOS to show the Accessibility prompt, if one is still pending.
    ///
    /// Returns the trust state *after* the call. A `false` here usually means
    /// the user has not yet flipped the switch in System Settings — the prompt
    /// does not wait for that, it only opens the door.
    @discardableResult
    static func request() -> Bool {
        // The Carbon constant is a mutable global; copy the key as a String so
        // Swift 6 does not treat this call as touching shared mutable state.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Opens Privacy & Security → Accessibility so the user can finish a grant
    /// the prompt alone did not complete.
    ///
    /// An `LSUIElement` app is never frontmost, so a bare `NSWorkspace.open`
    /// can leave System Settings behind the window the user is staring at —
    /// Teach then looks like it never opened the Accessibility list. Briefly
    /// becoming a regular app (same move as `FilePicker`) and asking the
    /// configuration to activate is what brings the list forward.
    static func openSystemSettings() {
        let previousPolicy = NSApp.activationPolicy()
        if previousPolicy != .regular {
            NSApp.setActivationPolicy(.regular)
        }
        NSApp.activate(ignoringOtherApps: true)

        for candidate in accessibilitySettingsURLCandidates {
            guard let url = URL(string: candidate) else { continue }
            // Trying every candidate until one reports success covers OS builds
            // that only recognise one of the schemes. Activation policy above
            // is what brings the list forward from an accessory app.
            if NSWorkspace.shared.open(url) {
                restoreActivationPolicy(previousPolicy)
                return
            }
        }

        let appURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(appURL, configuration: configuration) { _, _ in }
        restoreActivationPolicy(previousPolicy)
    }

    /// Restore the accessory policy after Settings has had a moment to come
    /// forward. Leaving `.regular` would put a Dock icon on an app that
    /// otherwise has none.
    private static func restoreActivationPolicy(_ previous: NSApplication.ActivationPolicy) {
        guard previous != .regular else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            if NSApp.activationPolicy() == .regular {
                NSApp.setActivationPolicy(previous)
            }
        }
    }

    /// Turns the extras on or off and keeps the event tap in step.
    static func setExtrasEnabled(_ enabled: Bool) {
        AppSettings.accessibilityExtrasEnabled = enabled
        if enabled {
            _ = request()
        }
        NotificationCenter.default.post(name: extrasChangedNotification, object: nil)
    }
}

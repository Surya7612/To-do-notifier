import ApplicationServices
import AppKit
import Foundation

/// Whether this process may use Accessibility APIs and a CGEvent tap.
///
/// Opt-in, never required. Carbon hotkeys and OCR pointing work without it.
/// When the user enables the extras in Settings *and* macOS trusts the process,
/// Tab+Q and the Move pointer / Click actions become available.
@MainActor
enum TrustAccessibility {
    /// Posted when the Settings toggle changes, so the event tap can install
    /// or tear down without polling.
    static let extrasChangedNotification = Notification.Name("TrustAccessibility.extrasChanged")

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
    static func openSystemSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_Accessibility",
        ]
        for candidate in candidates {
            if let url = URL(string: candidate), NSWorkspace.shared.open(url) { return }
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

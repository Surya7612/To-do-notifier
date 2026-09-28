import AppKit
import Foundation

/// Copy and actions for the Apple Reminders mirror Settings section.
///
/// Kept pure so the words in front of the user can be tested without EventKit.
nonisolated enum ReminderMirrorMessaging {
    /// Off-state explanation: what the feature is for, and that it is not a
    /// custom push app.
    static let offStateDetail = """
    Local notifications need this Mac awake at the due time. Turning this on \
    copies dated tasks into an iCloud Reminders list so Apple can alert your \
    iPhone and Watch instead — there is no separate push server. Only future \
    tasks are copied; completing one in Reminders does not tick it off in the \
    to-do app.
    """

    static func detail(for destination: AppleReminders.Destination,
                       listTitle: String = ReminderMirror.listTitle,
                       assistantName: String) -> String {
        switch destination {
        case let .syncing(account):
            return """
            Future dated tasks go into a “\(listTitle)” list in \(account). \
            Your iPhone and Watch get Apple’s alert even when this Mac is asleep. \
            \(assistantName) stands down for anything Reminders has taken on, so \
            one thing pings once. Check the Reminders app on your phone after \
            the first sync.
            """
        case let .thisMacOnly(account):
            return """
            Reminders is using the “\(account)” account on this Mac, which does \
            not sync — nothing will reach your phone. Turn on iCloud for \
            Reminders in System Settings → Apple Account → iCloud → Reminders \
            (or Calendars & Reminders), then flip this switch off and on again.
            """
        }
    }

    static func deniedDetail(assistantName: String) -> String {
        "Reminders access is off for \(assistantName). Open System Settings → Privacy & Security → Reminders (and Calendars if prompted) and allow access, then try again."
    }

    /// Opens the Privacy & Security pane for Reminders when possible.
    @MainActor
    static func openSystemSettingsForReminders() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Reminders",
        ]
        for raw in candidates {
            if let url = URL(string: raw), NSWorkspace.shared.open(url) { return }
        }
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(url)
        }
    }
}

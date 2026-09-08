import Foundation
import UserNotifications

/// Schedules the local notification behind a saved context's reminder.
///
/// Local only, and deliberately so. A reminder is a promise the app made to the
/// user, and the plan's remote scheduler exists for the case this cannot cover:
/// a Mac that is asleep when the time comes. Until that exists, saying plainly
/// that reminders need this machine awake is better than a cloud round trip for
/// something `UNUserNotificationCenter` already does.
enum Reminders {
    /// Carried on the notification so opening it can find the context again.
    static let contextIDKey = "savedContextID"
    private static let categoryID = "savedContextReminder"

    /// Asks once, the first time the user actually arms a reminder rather than
    /// at launch — a permission prompt makes more sense next to the thing that
    /// needs it.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()

        switch settings.authorizationStatus {
        case .authorized, .provisional:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    static var isDenied: Bool {
        get async {
            await UNUserNotificationCenter.current().notificationSettings()
                .authorizationStatus == .denied
        }
    }

    /// - Returns: whether the reminder was actually scheduled, so the caller can
    ///   tell the user when it was not instead of silently dropping it.
    static func schedule(id: String,
                         at date: Date,
                         intent: String,
                         sourceApp: String) async -> Bool {
        guard date > Date(), await requestAuthorization() else { return false }

        let content = UNMutableNotificationContent()
        // The user's own words are the notification. A model's summary here
        // would be putting words in their mouth at the one moment they are
        // least able to tell the difference.
        content.title = "You wanted to come back to this"
        content.body = intent
        content.subtitle = sourceApp
        content.sound = .default
        content.userInfo = [contextIDKey: id]
        content.categoryIdentifier = categoryID

        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute],
                                                         from: date)
        let request = UNNotificationRequest(
            identifier: id,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
            return true
        } catch {
            NSLog("[Reminders] couldn't schedule \(id): \(error)")
            return false
        }
    }

    static func cancel(id: String) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [id])
    }
}

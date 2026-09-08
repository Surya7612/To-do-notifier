import AppKit
import SwiftData
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var companion = CompanionPanelController(modelContext: ContextStore.shared.mainContext)

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        NSApp.setActivationPolicy(.accessory)

        // Set before any reminder can fire, or a notification arriving while the
        // app is running is swallowed instead of shown.
        UNUserNotificationCenter.current().delegate = self

        GlobalHotkey.shared.activate(AppSettings.hotkey) { [weak self] in
            self?.companion.toggle()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkey.shared.unregister()
    }
}

extension AppDelegate: UNUserNotificationCenterDelegate {
    /// macOS suppresses notifications from the foreground app by default. This
    /// app has no windows most of the time, so "foreground" is not a signal that
    /// the user has already seen anything.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    /// A reminder is only useful if it can take you back to what you saved, so
    /// opening one shows the library rather than just dismissing.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }

        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
            LibraryWindow.open()
        }
    }
}

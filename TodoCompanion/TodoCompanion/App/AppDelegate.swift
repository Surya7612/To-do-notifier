import AppKit
import SwiftData
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var companion = CompanionPanelController(modelContext: ContextStore.shared.mainContext)

    private var storeObserver: NSObjectProtocol?
    private var republishTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        NSApp.setActivationPolicy(.accessory)

        // Set before any reminder can fire, or a notification arriving while the
        // app is running is swallowed instead of shown.
        UNUserNotificationCenter.current().delegate = self

        GlobalHotkey.shared.activate(AppSettings.hotkey) { [weak self] in
            self?.companion.toggle()
        }

        watchForProjectChanges()
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkey.shared.unregister()
    }

    /// Keeps the file the to-do app reads in step with the store.
    ///
    /// Driven off saves rather than called from each place that edits a project,
    /// because those are spread across the panel and the library and a new one
    /// that forgot to publish would leave the other app quietly showing stale
    /// names — the kind of bug nothing surfaces.
    private func watchForProjectChanges() {
        ProjectExport.publish(from: ContextStore.shared.mainContext)

        storeObserver = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleRepublish() }
        }
    }

    /// Coalesced because a single save often arrives in a burst — inserting a
    /// context, then its summary landing a moment later — and each would
    /// otherwise rewrite the same file.
    private func scheduleRepublish() {
        republishTask?.cancel()
        republishTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            ProjectExport.publish(from: ContextStore.shared.mainContext)
        }
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

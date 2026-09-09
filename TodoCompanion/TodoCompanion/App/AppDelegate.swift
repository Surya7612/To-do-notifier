import AppKit
import SwiftData
import SwiftUI
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var companion = CompanionPanelController(modelContext: ContextStore.shared.mainContext)

    private var storeObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var republishTask: Task<Void, Never>?
    private var wakeSweepTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppSettings.registerDefaults()
        NSApp.setActivationPolicy(.accessory)

        // Set before any reminder can fire, or a notification arriving while the
        // app is running is swallowed instead of shown.
        UNUserNotificationCenter.current().delegate = self

        GlobalHotkey.shared.activate(AppSettings.hotkey) { [weak self] in
            self?.companion.toggle()
        }
        GlobalHotkey.shared.activate(AppSettings.talkHotkey, for: .talk) { [weak self] in
            self?.companion.summonAndListen()
        }

        watchForProjectChanges()
        watchForWake()

        // Anything captured on the phone while this Mac was asleep is waiting
        // in the folder, so launch is the moment to collect it.
        InboxImporter.importAll(into: ContextStore.shared.mainContext)

        mirrorTasksToAppleReminders()
    }

    /// Collects the phone inbox again when the Mac comes back from sleep.
    ///
    /// Launch was the only *unattended* trigger, and this app is built to stay
    /// running — so on the machine it is actually used on, launch happens once
    /// and then never again for days. A capture that landed while the lid was
    /// shut therefore waited for the next summon or for the library to be
    /// opened, which is the one moment the user has no reason to do either:
    /// they have just sat down, and what they sent themselves last night is
    /// what they sat down to deal with.
    ///
    /// It matters most for the case that fails *silently*. An imported reminder
    /// whose time has already passed is recorded but deliberately not
    /// scheduled, because a non-repeating calendar trigger in the past has no
    /// next matching date and would never fire anyway — so "remind me in 30
    /// minutes", sent to a sleeping Mac, is not merely late, it is gone. Waking
    /// is the last moment at which it can still be caught.
    ///
    /// Still not a poll, on the same footing as the launch sweep: it runs when
    /// the machine does something, not on a timer.
    private func watchForWake() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.sweepAfterWake() }
        }
    }

    /// The inbox is read a few times over the first couple of minutes awake,
    /// which is not defensiveness about the folder — it is a fact about what
    /// wakes up when. Wi-Fi associates and iCloud starts syncing *after* the
    /// wake notification fires, so a single read at that instant reliably finds
    /// the folder exactly as empty as it was before the Mac went to sleep.
    ///
    /// Bounded rather than repeating, so this cannot become the background
    /// worker the app otherwise refuses to have. If nothing has arrived by the
    /// last attempt, the ordinary triggers take over again.
    private func sweepAfterWake() {
        wakeSweepTask?.cancel()
        wakeSweepTask = Task { [weak self] in
            for delay in [Duration.seconds(0), .seconds(15), .seconds(45), .seconds(120)] {
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                }
                guard !Task.isCancelled, let self else { return }

                InboxImporter.importAll(into: ContextStore.shared.mainContext)
                self.mirrorTasksToAppleReminders()
            }
        }
    }

    /// Catches up the Apple Reminders list without waiting to be summoned.
    ///
    /// The mirror otherwise runs only on summon, which is the wrong moment for
    /// the one thing it is for: a reminder set just before the lid closes is
    /// still due when the Mac comes back, and nothing would have told the phone
    /// because nobody pressed the hotkey in between. Launch is also when the
    /// to-do app's file is most likely to have moved on without this app
    /// looking — it is a different process, and it has been writing while this
    /// one was not running.
    ///
    /// Still not a background poll: it happens once, at launch, in the same
    /// place the phone inbox is collected, rather than on a timer.
    private func mirrorTasksToAppleReminders() {
        guard AppSettings.mirrorsToAppleReminders, AppleReminders.isAuthorized else { return }

        let work = TodoBridge.load()
        let todos = work.todos + ProjectExport.anticipatedTasks(
            for: ProjectExport.pendingReminders(in: ContextStore.shared.mainContext),
            knownTo: work.todos
        )

        Task {
            do {
                let armed = try await AppleReminders.sync(openTodos: todos,
                                                          quietHours: work.quietHours)
                // Apple announces what it has taken on, so this app must not
                // also announce it — the same rule the panel applies on summon.
                for identifier in ProjectExport.reminderIdentifiers(inTaskIDs: armed) {
                    Reminders.cancel(id: identifier)
                }
            } catch {
                // Nothing is on screen at launch to tell, and Settings is where
                // the state of this is reported.
                NSLog("[AppleReminders] launch mirror failed: \(error)")
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GlobalHotkey.shared.unregister()
        wakeSweepTask?.cancel()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
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

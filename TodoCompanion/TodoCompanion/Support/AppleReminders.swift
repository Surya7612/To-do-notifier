import EventKit
import Foundation

/// Writes the mirrored task list into Apple Reminders.
///
/// Everything about *what* belongs there lives in `ReminderMirror`; this is the
/// part that talks to EventKit and so cannot be tested without a real database.
@MainActor
enum AppleReminders {
    /// Whether a written reminder will actually reach another device.
    ///
    /// Worth its own case rather than a bool, because the failure is silent and
    /// total: Reminders can be running on a **local** account that never leaves
    /// this Mac, in which case every part of this feature works and the phone
    /// never hears about any of it. Stated in Settings instead of discovered.
    enum Destination: Equatable {
        case syncing(account: String)
        case thisMacOnly(account: String)

        var reachesOtherDevices: Bool {
            switch self {
            case .syncing: true
            case .thisMacOnly: false
            }
        }

        var account: String {
            switch self {
            case let .syncing(account), let .thisMacOnly(account): account
            }
        }
    }

    enum MirrorFailure: LocalizedError {
        case accessDenied
        case noRemindersAccount

        var errorDescription: String? {
            switch self {
            case .accessDenied:
                "Reminders access was refused, so tasks cannot be sent to your other devices."
            case .noRemindersAccount:
                "No Reminders account was found on this Mac."
            }
        }
    }

    private static let store = EKEventStore()

    static var isDenied: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .denied
    }

    static var isAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .reminder) == .fullAccess
    }

    /// Asked the first time the user turns mirroring on, next to the switch
    /// that needs it, rather than at launch.
    static func requestAccess() async -> Bool {
        if isAuthorized { return true }
        return (try? await store.requestFullAccessToReminders()) ?? false
    }

    /// Which account the list lives in, and therefore whether it travels.
    static func destination() -> Destination? {
        guard let source = preferredSource() else { return nil }
        return source.sourceType == .local
            ? .thisMacOnly(account: source.title)
            : .syncing(account: source.title)
    }

    /// Brings Apple Reminders in line with the to-do app's list.
    ///
    /// - Returns: the tasks Apple is now armed to announce. The caller needs
    ///   the *facts*, not a count, because standing its own notification down
    ///   for something that turned out not to be mirrored would lose a reminder
    ///   altogether.
    @discardableResult
    static func sync(openTodos: [LinkedTodo], quietHours: QuietHours) async throws -> [String] {
        guard isAuthorized else { throw MirrorFailure.accessDenied }
        guard let calendar = try mirroredList() else { throw MirrorFailure.noRemindersAccount }

        let existing = await fetchMirrored(in: calendar)
        let mirrorable = ReminderMirror.mirrorable(openTodos, quietHours: quietHours)
        let plan = ReminderMirror.plan(
            openTodos: openTodos,
            mirrorable: mirrorable,
            existing: existing.values.map(\.value)
        )
        let armed = mirrorable.map(\.taskID)
        if plan.isEmpty { return armed }

        for task in plan.create {
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = calendar
            apply(task, to: reminder)
            try store.save(reminder, commit: false)
        }

        for task in plan.update {
            guard let reminder = existing[task.taskID]?.reminder else { continue }
            apply(task, to: reminder)
            try store.save(reminder, commit: false)
        }

        for taskID in plan.withdraw {
            guard let reminder = existing[taskID]?.reminder else { continue }
            try store.remove(reminder, commit: false)
        }

        // One commit for the batch: each save would otherwise be its own write
        // to a database iCloud is syncing.
        try store.commit()

        return armed
    }

    /// Removes everything this app put there, for turning the feature off.
    ///
    /// Reminders the user created themselves in the same list are left alone,
    /// since the match is on this app's own url rather than on the list.
    static func withdrawAll() async throws {
        guard isAuthorized, let calendar = try mirroredList() else { return }

        let existing = await fetchMirrored(in: calendar)
        guard !existing.isEmpty else { return }

        for entry in existing.values {
            try store.remove(entry.reminder, commit: false)
        }
        try store.commit()
    }

    private static func apply(_ task: MirroredTask, to reminder: EKReminder) {
        reminder.title = task.title
        reminder.url = ReminderMirror.url(forTaskID: task.taskID)

        // Both a due date and an alarm. The due date is what Reminders sorts
        // and groups by; only the alarm actually notifies anyone.
        reminder.dueDateComponents = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: task.alarmAt
        )
        reminder.alarms?.forEach(reminder.removeAlarm)
        reminder.addAlarm(EKAlarm(absoluteDate: task.alarmAt))
    }

    private struct Entry {
        var reminder: EKReminder
        var value: ExistingMirroredTask
    }

    private static func fetchMirrored(in calendar: EKCalendar) async -> [String: Entry] {
        let predicate = store.predicateForReminders(in: [calendar])
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                continuation.resume(returning: found ?? [])
            }
        }

        var entries: [String: Entry] = [:]
        for reminder in reminders {
            guard let taskID = ReminderMirror.taskID(from: reminder.url) else { continue }
            let alarmAt = reminder.alarms?.first?.absoluteDate
                ?? reminder.dueDateComponents.flatMap(Calendar.current.date(from:))
                ?? .distantPast
            entries[taskID] = Entry(
                reminder: reminder,
                value: ExistingMirroredTask(taskID: taskID,
                                            title: reminder.title ?? "",
                                            alarmAt: alarmAt,
                                            isCompletedInReminders: reminder.isCompleted)
            )
        }
        return entries
    }

    private static func mirroredList() throws -> EKCalendar? {
        guard let source = preferredSource() else { return nil }

        if let found = store.calendars(for: .reminder).first(where: {
            $0.title == ReminderMirror.listTitle && $0.source == source
        }) {
            return found
        }

        // A list of this app's own rather than the user's default one, so
        // turning the feature off can take back exactly what it added and
        // nothing beside it.
        let calendar = EKCalendar(for: .reminder, eventStore: store)
        calendar.title = ReminderMirror.listTitle
        calendar.source = source
        try store.saveCalendar(calendar, commit: true)
        return calendar
    }

    /// An account that syncs, in preference to one that does not.
    ///
    /// The default list for new reminders is *not* the right choice: it may sit
    /// in the local account, and a reminder there is invisible to the phone,
    /// which is the entire point of writing it.
    private static func preferredSource() -> EKSource? {
        let sources = store.sources
        return sources.first { $0.sourceType == .calDAV && $0.title.caseInsensitiveCompare("iCloud") == .orderedSame }
            ?? sources.first { $0.sourceType == .calDAV }
            ?? sources.first { $0.sourceType == .exchange }
            ?? store.defaultCalendarForNewReminders()?.source
            ?? sources.first { $0.sourceType == .local }
    }
}

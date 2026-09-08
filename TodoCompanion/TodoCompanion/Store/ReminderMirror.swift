import Foundation

/// One task as it should appear in Apple Reminders.
struct MirroredTask: Equatable, Sendable {
    /// The to-do app's own identifier. Carried across so a reminder can be
    /// matched back to the task it stands for, rather than by title — two tasks
    /// can share a title, and retitling one must not orphan its reminder.
    var taskID: String
    var title: String
    var alarmAt: Date
}

/// A reminder already sitting in the mirrored list.
///
/// A value type rather than an `EKReminder` so the decisions below can be
/// tested without a Reminders database, an iCloud account, or a permission
/// prompt.
struct ExistingMirroredTask: Equatable, Sendable {
    var taskID: String
    var title: String
    var alarmAt: Date
    var isCompletedInReminders: Bool
}

/// What to create, change and withdraw in Apple Reminders.
struct MirrorPlan: Equatable, Sendable {
    var create: [MirroredTask] = []
    var update: [MirroredTask] = []
    var withdraw: [String] = []

    var isEmpty: Bool { create.isEmpty && update.isEmpty && withdraw.isEmpty }
}

/// Decides which of the to-do app's tasks belong in Apple Reminders, so an
/// alert can reach the user on a device this Mac is not.
///
/// This is the one thing local notifications cannot do: `UNUserNotificationCenter`
/// needs this machine awake at the moment a task is due, which the plan admits
/// outright and earmarks a hosted scheduler to fix. Apple already runs that
/// scheduler. A reminder written into an iCloud list is delivered by Apple to
/// the phone and the watch whether this Mac is asleep, shut, or elsewhere — with
/// no server, no push certificate, and no paid developer programme.
///
/// It is a publish, in the same shape as `ProjectExport`: another program owns
/// delivery, and nothing is ever read back as truth. Completing a mirrored
/// reminder on the phone silences Apple's alert and leaves the task open in the
/// app that owns tasks, which is stated in the UI rather than papered over —
/// reading completion back would make Reminders a second source of truth for
/// what is done.
nonisolated enum ReminderMirror {
    /// The list Apple syncs. Named for the app rather than the assistant,
    /// because these are the to-do app's tasks and that is the list the user
    /// will see on their phone.
    static let listTitle = "To-Do Notifier"

    /// Written into each reminder's `url` so it can be matched back to its
    /// task. Kept on the item itself rather than in a local map deliberately:
    /// the map would be this Mac's private state, and a reminder edited or
    /// moved on another device would come back unrecognizable.
    private static let scheme = "todonotifier"

    static func url(forTaskID taskID: String) -> URL? {
        URL(string: "\(scheme)://task/\(taskID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? taskID)")
    }

    static func taskID(from url: URL?) -> String? {
        guard let url, url.scheme == scheme else { return nil }
        let identifier = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !identifier.isEmpty else { return nil }
        return identifier.removingPercentEncoding ?? identifier
    }

    /// The tasks worth putting in front of someone who is away from this Mac.
    ///
    /// Only tasks still ahead of us, and that bound is not tidiness: an
    /// `EKAlarm` set to a time already past is delivered as soon as it syncs, so
    /// mirroring a backlog would fire every overdue task at once, on every
    /// device, the moment the feature was switched on. An overdue task is
    /// already being nagged about here by the app that owns it.
    static func mirrorable(_ todos: [LinkedTodo],
                           quietHours: QuietHours,
                           now: Date = Date(),
                           calendar: Calendar = .current) -> [MirroredTask] {
        todos
            .compactMap { todo -> MirroredTask? in
                guard !todo.isDone,
                      let dueAt = todo.dueAt,
                      dueAt > now,
                      !todo.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return nil }

                // The same do-not-disturb window the user configured once, in
                // the app that owns notification preferences. A third
                // notification system ignoring it would make the setting a lie
                // in the one place the user cannot see it being ignored.
                return MirroredTask(
                    taskID: todo.id,
                    title: todo.title,
                    alarmAt: quietHours.firstMomentAfter(dueAt, calendar: calendar)
                )
            }
            .sorted { $0.alarmAt < $1.alarmAt }
    }

    /// Compares what should be there with what is.
    ///
    /// Withdrawal keys on the task having gone from the *open* list — done or
    /// deleted over there — and deliberately not on it having stopped being
    /// mirrorable. Those are different facts that look alike: a task simply
    /// becoming due would drop out of `mirrorable`, and treating that as
    /// withdrawal would delete each reminder at the very moment it was worth
    /// having.
    static func plan(openTodos: [LinkedTodo],
                     mirrorable: [MirroredTask],
                     existing: [ExistingMirroredTask]) -> MirrorPlan {
        let known = Dictionary(existing.map { ($0.taskID, $0) }, uniquingKeysWith: { first, _ in first })
        let stillListed = Set(openTodos.filter { !$0.isDone }.map(\.id))

        var plan = MirrorPlan()

        for task in mirrorable {
            guard let current = known[task.taskID] else {
                plan.create.append(task)
                continue
            }
            // Left alone once ticked off on another device. Rewriting it would
            // un-complete something the user finished, and re-arming an alarm
            // they have already dealt with is worse than the list looking
            // slightly stale.
            guard !current.isCompletedInReminders else { continue }

            if current.title != task.title || current.alarmAt != task.alarmAt {
                plan.update.append(task)
            }
        }

        plan.withdraw = existing
            .map(\.taskID)
            .filter { !stillListed.contains($0) }

        return plan
    }
}

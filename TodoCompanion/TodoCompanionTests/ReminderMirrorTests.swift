import Foundation
import Testing

@testable import TodoCompanion

/// What gets copied into Apple Reminders, and what gets taken back.
///
/// This is the only part of the app that writes into something Apple syncs to
/// other devices, and every failure here is loud in the user's pocket rather
/// than on screen: a stale reminder alerts for work already done, and a
/// backlog mirrored with times in the past alerts for all of it at once.
@Suite struct ReminderMirrorTests {
    private func todo(_ id: String,
                      _ title: String,
                      dueIn seconds: TimeInterval?,
                      done: Bool = false) -> LinkedTodo {
        LinkedTodo(id: id,
                   title: title,
                   dueAt: seconds.map { Date().addingTimeInterval($0) },
                   isDone: done)
    }

    @Test func copiesATaskThatIsStillAhead() {
        let mirrored = ReminderMirror.mirrorable([todo("1", "Finish the write-up", dueIn: 3_600)],
                                                 quietHours: QuietHours())

        #expect(mirrored.count == 1)
        #expect(mirrored.first?.taskID == "1")
        #expect(mirrored.first?.title == "Finish the write-up")
    }

    @Test func anOverdueTaskIsNotCopied() {
        // Not tidiness. An EKAlarm whose date has passed is delivered as soon as
        // it syncs, so mirroring a backlog would fire every overdue task at
        // once, on every device, the moment the feature was switched on.
        let mirrored = ReminderMirror.mirrorable([todo("1", "Weeks late", dueIn: -86_400)],
                                                 quietHours: QuietHours())

        #expect(mirrored.isEmpty)
    }

    @Test func aFinishedOrUndatedTaskIsNotCopied() {
        let mirrored = ReminderMirror.mirrorable([
            todo("1", "Already done", dueIn: 3_600, done: true),
            todo("2", "Someday", dueIn: nil),
            todo("3", "   ", dueIn: 3_600),
        ], quietHours: QuietHours())

        #expect(mirrored.isEmpty)
    }

    @Test func quietHoursMoveTheAlarmJustLikeALocalReminder() {
        // The user configured do-not-disturb once, in the app that owns
        // notification preferences. A third notification system ignoring it
        // would make the setting a lie somewhere the user cannot see.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let quiet = QuietHours(isEnabled: true, startHour: 22, endHour: 7)
        let midnight = calendar.date(from: DateComponents(year: 2030, month: 1, day: 1, hour: 0, minute: 30))!
        let due = LinkedTodo(id: "1", title: "Small hours", dueAt: midnight, isDone: false)

        let mirrored = ReminderMirror.mirrorable([due],
                                                 quietHours: quiet,
                                                 now: midnight.addingTimeInterval(-3_600),
                                                 calendar: calendar)

        #expect(calendar.component(.hour, from: mirrored[0].alarmAt) == 7)
    }

    @Test func matchesAReminderBackToItsTaskByURL() {
        // On the item rather than in a local map, so a reminder edited on
        // another device still comes back recognizable.
        let url = ReminderMirror.url(forTaskID: "companion:ABC-123")

        #expect(ReminderMirror.taskID(from: url) == "companion:ABC-123")
        #expect(ReminderMirror.taskID(from: URL(string: "https://example.com/task/1")) == nil)
        #expect(ReminderMirror.taskID(from: nil) == nil)
    }

    @Test func createsWhatIsMissingAndLeavesTheRestAlone() {
        let tasks = [todo("1", "One", dueIn: 3_600), todo("2", "Two", dueIn: 7_200)]
        let mirrorable = ReminderMirror.mirrorable(tasks, quietHours: QuietHours())
        let alreadyThere = ExistingMirroredTask(taskID: "1",
                                                title: "One",
                                                alarmAt: mirrorable[0].alarmAt,
                                                isCompletedInReminders: false)

        let plan = ReminderMirror.plan(openTodos: tasks, mirrorable: mirrorable, existing: [alreadyThere])

        #expect(plan.create.map(\.taskID) == ["2"])
        #expect(plan.update.isEmpty)
        #expect(plan.withdraw.isEmpty)
    }

    @Test func aRetitledOrRescheduledTaskIsUpdatedInPlace() {
        let tasks = [todo("1", "The new title", dueIn: 3_600)]
        let mirrorable = ReminderMirror.mirrorable(tasks, quietHours: QuietHours())
        let stale = ExistingMirroredTask(taskID: "1",
                                         title: "The old title",
                                         alarmAt: mirrorable[0].alarmAt.addingTimeInterval(-600),
                                         isCompletedInReminders: false)

        let plan = ReminderMirror.plan(openTodos: tasks, mirrorable: mirrorable, existing: [stale])

        #expect(plan.create.isEmpty)
        #expect(plan.update.map(\.title) == ["The new title"])
    }

    @Test func withdrawsAReminderForATaskCompletedOrDeletedInTheToDoApp() {
        let plan = ReminderMirror.plan(
            openTodos: [todo("1", "Ticked off over there", dueIn: 3_600, done: true)],
            mirrorable: [],
            existing: [ExistingMirroredTask(taskID: "1",
                                            title: "Ticked off over there",
                                            alarmAt: Date().addingTimeInterval(3_600),
                                            isCompletedInReminders: false),
                       ExistingMirroredTask(taskID: "gone",
                                            title: "Deleted over there",
                                            alarmAt: Date().addingTimeInterval(3_600),
                                            isCompletedInReminders: false)]
        )

        #expect(Set(plan.withdraw) == ["1", "gone"])
    }

    @Test func aTaskMerelyFallingDueIsNotWithdrawn() {
        // The failure this pins is deleting every reminder at the exact moment
        // it became worth having: a task simply reaching its due time drops out
        // of `mirrorable`, which looks identical to being finished if you key
        // withdrawal on that rather than on the task leaving the open list.
        let due = todo("1", "Due any second", dueIn: -30)
        let existing = ExistingMirroredTask(taskID: "1",
                                            title: "Due any second",
                                            alarmAt: Date().addingTimeInterval(-30),
                                            isCompletedInReminders: false)

        let plan = ReminderMirror.plan(openTodos: [due], mirrorable: [], existing: [existing])

        #expect(plan.withdraw.isEmpty)
    }

    @Test func oneCompletedOnThePhoneIsLeftCompleted() {
        // Rewriting it would un-complete something the user finished and re-arm
        // an alarm they have already dealt with.
        let tasks = [todo("1", "Renamed since", dueIn: 3_600)]
        let mirrorable = ReminderMirror.mirrorable(tasks, quietHours: QuietHours())
        let doneOnPhone = ExistingMirroredTask(taskID: "1",
                                               title: "The old title",
                                               alarmAt: mirrorable[0].alarmAt,
                                               isCompletedInReminders: true)

        let plan = ReminderMirror.plan(openTodos: tasks, mirrorable: mirrorable, existing: [doneOnPhone])

        #expect(plan.isEmpty)
    }

    @Test func onlyThisAppsOwnRemindersAreStoodDownFor() {
        // Which of the mirrored tasks came from a reminder set in this app, and
        // therefore already has a local notification to cancel. A loose match
        // would silence a reminder Apple never took on.
        let identifiers = ProjectExport.reminderIdentifiers(inTaskIDs: [
            "companion:ABC",
            "an-ordinary-task",
            "companion:",
            "not-companion:DEF",
        ])

        #expect(identifiers == ["ABC"])
    }
}

import Foundation
import Testing
@testable import TodoCompanion

/// Mirrors `inQuietHours` in `electron/lib/dataMerge.cjs`.
///
/// Two notification systems reading the same setting differently is worse than
/// only one of them honouring it, because the disagreement is invisible. These
/// tests pin the shared semantics, including the odd corner where an equal
/// start and end means "never quiet" rather than "always quiet".
@Suite("Quiet hours")
struct QuietHoursTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }

    private func date(hour: Int, day: Int = 8) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 9, day: day, hour: hour))!
    }

    @Test("disabled quiet hours never apply")
    func disabledIsNeverQuiet() {
        let hours = QuietHours(isEnabled: false, startHour: 22, endHour: 7)

        #expect(!hours.contains(date(hour: 2), calendar: calendar))
        #expect(!hours.contains(date(hour: 23), calendar: calendar))
    }

    @Test("an overnight window wraps past midnight")
    func overnightWindowWraps() {
        let hours = QuietHours(isEnabled: true, startHour: 22, endHour: 7)

        #expect(hours.contains(date(hour: 22), calendar: calendar), "start is inclusive")
        #expect(hours.contains(date(hour: 23), calendar: calendar))
        #expect(hours.contains(date(hour: 0), calendar: calendar))
        #expect(hours.contains(date(hour: 6), calendar: calendar))
        #expect(!hours.contains(date(hour: 7), calendar: calendar), "end is exclusive")
        #expect(!hours.contains(date(hour: 12), calendar: calendar))
        #expect(!hours.contains(date(hour: 21), calendar: calendar))
    }

    @Test("a same-day window does not wrap")
    func daytimeWindowDoesNotWrap() {
        let hours = QuietHours(isEnabled: true, startHour: 9, endHour: 17)

        #expect(hours.contains(date(hour: 9), calendar: calendar))
        #expect(hours.contains(date(hour: 16), calendar: calendar))
        #expect(!hours.contains(date(hour: 17), calendar: calendar))
        #expect(!hours.contains(date(hour: 3), calendar: calendar))
    }

    /// Matches the other app rather than being defensible on its own: an equal
    /// start and end reads as "no quiet hours". Treating it as a full 24 hours
    /// would silence every reminder from a setting that looks like a no-op.
    @Test("an equal start and end means never quiet")
    func equalBoundsAreNeverQuiet() {
        let hours = QuietHours(isEnabled: true, startHour: 5, endHour: 5)

        #expect(!hours.contains(date(hour: 5), calendar: calendar))
        #expect(!hours.contains(date(hour: 17), calendar: calendar))
    }

    @Test("a time outside quiet hours is left exactly as it is")
    func nonQuietTimesAreUnchanged() {
        let hours = QuietHours(isEnabled: true, startHour: 22, endHour: 7)
        let noon = date(hour: 12)

        #expect(hours.firstMomentAfter(noon, calendar: calendar) == noon)
    }

    @Test("a reminder inside the window moves to when it ends")
    func quietTimesMoveToTheEnd() {
        let hours = QuietHours(isEnabled: true, startHour: 22, endHour: 7)
        let moved = hours.firstMomentAfter(date(hour: 2), calendar: calendar)

        #expect(calendar.component(.hour, from: moved) == 7)
        // 2am on the 8th, so seven the same morning, not the next one.
        #expect(calendar.component(.day, from: moved) == 8)
    }

    @Test("a late-evening reminder moves to the next morning, not backwards")
    func lateEveningRollsToTomorrow() {
        let hours = QuietHours(isEnabled: true, startHour: 22, endHour: 7)
        let moved = hours.firstMomentAfter(date(hour: 23), calendar: calendar)

        #expect(calendar.component(.hour, from: moved) == 7)
        #expect(calendar.component(.day, from: moved) == 9, "must not move a reminder into the past")
    }

    @Test("moving a reminder always lands outside the window")
    func movedRemindersAreNeverStillQuiet() {
        let hours = QuietHours(isEnabled: true, startHour: 22, endHour: 7)

        for hour in 0..<24 {
            let moved = hours.firstMomentAfter(date(hour: hour), calendar: calendar)
            #expect(!hours.contains(moved, calendar: calendar), "\(hour):00 moved into quiet hours")
            #expect(moved >= date(hour: hour), "\(hour):00 moved backwards")
        }
    }
}

@Suite("Project task links")
struct ProjectTaskLinkTests {
    private func work(ids: [String]) -> LinkedWork {
        LinkedWork(todos: ids.map { LinkedTodo(id: $0, title: "task \($0)", dueAt: nil, isDone: false) })
    }

    @Test("linked tasks resolve in the to-do app's own order")
    func resolvesInSourceOrder() {
        let resolved = work(ids: ["a", "b", "c"]).todos(withIDs: ["c", "a"])

        #expect(resolved.map(\.id) == ["a", "c"])
    }

    /// The other app owns that file and can delete a task at any time. A
    /// dangling link must not become an empty row or a crash.
    @Test("a task deleted in the other app simply stops resolving")
    func danglingLinksAreSkipped() {
        let resolved = work(ids: ["a"]).todos(withIDs: ["a", "deleted-over-there"])

        #expect(resolved.map(\.id) == ["a"])
    }

    @Test("no links resolves to nothing")
    func noLinksResolveToNothing() {
        #expect(work(ids: ["a", "b"]).todos(withIDs: []).isEmpty)
    }
}

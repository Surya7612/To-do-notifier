import Foundation
import Testing
@testable import TodoCompanion

/// Recall decides what the model is told the user kept. Too eager and a
/// question about the screen arrives buried under a list of old keeps; too
/// reluctant and "what was I researching yesterday?" gets an invented answer.
/// The clock is fixed so day boundaries are asserted, not hoped for.
@Suite("Library recall")
@MainActor
struct LibraryRecallTests {
    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        calendar.firstWeekday = 1
        return calendar
    }

    /// Wednesday 14 October 2026, 15:00 New York.
    private static let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 15))!

    private func kept(_ intent: String, hoursAgo: Double, topics: [String] = []) -> SavedContext {
        let context = Fixture.saved(intent: intent, topics: topics)
        context.createdAt = Self.now.addingTimeInterval(-hoursAgo * 3_600)
        return context
    }

    @Test("past-tense questions about keeping or working are recall",
          arguments: [
              "What was I researching yesterday?",
              "what did I save for this project",
              "Did I keep anything about passports?",
              "show me what I saved last week",
              "what have I been working on? my saves please",
              "I saved something about closures, what was it",
          ])
    func recognisesRecall(_ question: String) {
        #expect(LibraryRecall.isRecallQuestion(question))
    }

    @Test("present-tense questions about the screen are not recall",
          arguments: [
              "How do I save this file?",
              "What should I work on next?",
              "what is this error",
              "Explain what this is, in plain language",
              "how do I keep the panel open",
          ])
    func leavesScreenQuestionsAlone(_ question: String) {
        #expect(!LibraryRecall.isRecallQuestion(question))
    }

    @Test("yesterday is the whole previous calendar day and nothing else")
    func yesterdayWindow() throws {
        let window = try #require(LibraryRecall.timeWindow(in: "what did I save yesterday",
                                                           now: Self.now, calendar: Self.calendar))
        let startOfToday = Self.calendar.startOfDay(for: Self.now)
        #expect(window.interval.end == startOfToday)
        #expect(window.interval.duration == 86_400)
        #expect(window.phrase == "yesterday")
    }

    @Test("a current period ends now, not at its end")
    func thisWeekEndsNow() throws {
        let window = try #require(LibraryRecall.timeWindow(in: "what did I keep this week",
                                                           now: Self.now, calendar: Self.calendar))
        #expect(window.interval.end == Self.now)
    }

    @Test("a weekday means the most recent one before today")
    func weekdayIsInThePast() throws {
        let window = try #require(LibraryRecall.timeWindow(in: "what was I working on on monday",
                                                           now: Self.now, calendar: Self.calendar))
        #expect(Self.calendar.component(.weekday, from: window.interval.start) == 2)
        #expect(window.interval.end <= Self.calendar.startOfDay(for: Self.now))

        let sameDay = try #require(LibraryRecall.timeWindow(in: "what did I save last wednesday",
                                                            now: Self.now, calendar: Self.calendar))
        #expect(sameDay.interval.end <= Self.calendar.startOfDay(for: Self.now))
    }

    @Test("a question naming no time has no window")
    func noWindow() {
        #expect(LibraryRecall.timeWindow(in: "what did I save about passports",
                                         now: Self.now, calendar: Self.calendar) == nil)
    }

    @Test("the time window is a filter: a keep outside it is not a weaker answer, it is no answer")
    func windowFilters() {
        let yesterday = kept("read the engram paper", hoursAgo: 20)
        let lastWeek = kept("renew passport", hoursAgo: 24 * 8)

        let matches = LibraryRecall.matches(for: "what was I researching yesterday?",
                                            among: [lastWeek, yesterday],
                                            now: Self.now, calendar: Self.calendar)

        #expect(matches.map(\.context.intent) == ["read the engram paper"])
        #expect(matches.first?.reason.contains("kept yesterday") == true)
    }

    @Test("subject words rank within the window, and the user's words outrank the model's")
    func subjectRanks() throws {
        let statedMatch = kept("compare retrieval scoring approaches", hoursAgo: 30)
        let glossMatch = kept("look at this later", hoursAgo: 26)
        glossMatch.aiSummary = "A blog post about retrieval"
        let unrelated = kept("buy milk", hoursAgo: 28)

        let matches = LibraryRecall.matches(for: "what did I save about retrieval this week",
                                            among: [glossMatch, unrelated, statedMatch],
                                            now: Self.now, calendar: Self.calendar)

        #expect(matches.map(\.context.intent) == ["compare retrieval scoring approaches", "look at this later"])
        #expect(try #require(matches.first).reason.contains("mentions retrieval"))
    }

    @Test("a bare 'what did I save' returns the newest keeps, labelled recent")
    func bareRecallIsRecent() throws {
        let older = kept("older", hoursAgo: 50)
        let newer = kept("newer", hoursAgo: 2)

        let matches = LibraryRecall.matches(for: "what did I save?",
                                            among: [older, newer],
                                            now: Self.now, calendar: Self.calendar)

        #expect(matches.map(\.context.intent) == ["newer", "older"])
        #expect(try #require(matches.first).reason == "recent")
    }

    @Test("'this project' narrows to the chosen project, and is ignored without one")
    func projectScope() {
        let project = Project(name: "Engram")
        let inProject = kept("design the graph view", hoursAgo: 3)
        inProject.project = project
        let elsewhere = kept("plan the trip", hoursAgo: 4)

        let scoped = LibraryRecall.matches(for: "what did I save for this project",
                                           among: [inProject, elsewhere],
                                           inProject: project,
                                           now: Self.now, calendar: Self.calendar)
        #expect(scoped.map(\.context.intent) == ["design the graph view"])
        #expect(scoped.first?.reason.contains("in Engram") == true)

        let unscoped = LibraryRecall.matches(for: "what did I save for this project",
                                             among: [inProject, elsewhere],
                                             now: Self.now, calendar: Self.calendar)
        #expect(unscoped.count == 2)
    }

    @Test("a screen question yields no recall at all, whatever is in the library")
    func screenQuestionRecallsNothing() {
        let keep = kept("save the closure notes", hoursAgo: 1)
        #expect(LibraryRecall.matches(for: "how do I save this?", among: [keep],
                                      now: Self.now, calendar: Self.calendar).isEmpty)
    }

    @Test("an empty search tells the model to say so rather than invent")
    func emptyScopeNote() {
        let note = LibraryRecall.scopeNote(for: "what did I save yesterday", found: 0,
                                           projectName: nil, now: Self.now, calendar: Self.calendar)
        #expect(note.contains("found nothing"))
        #expect(note.contains("do not invent"))
        #expect(note.contains("yesterday"))
    }

    @Test("the scope note reaches the prompt ahead of the keeps")
    func noteInPrompt() throws {
        var context = AskContext()
        context.recallNote = "RECALL NOTE"
        context.memories = ["- \"read the paper\" (saved yesterday from Safari)"]

        let prompt = Prompt.user(question: "what did I save yesterday", context: context)
        let note = try #require(prompt.range(of: "RECALL NOTE"))
        let keeps = try #require(prompt.range(of: "read the paper"))
        #expect(note.lowerBound < keeps.lowerBound)
    }
}

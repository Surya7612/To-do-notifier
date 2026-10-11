import Foundation
import Testing
@testable import TodoCompanion

/// "What should I work on?" is answered from the user's own task list. The
/// failures are a generic productivity lecture (not recognised), a screen
/// question hijacked into planning (too eager), and a time budget misread.
@Suite("What to work on next")
@MainActor
struct FocusPlanTests {
    @Test("asking what to do next is recognised",
          arguments: [
              "I have 45 minutes. What should I work on?",
              "what do I tackle first",
              "Where should I start today?",
              "plan my next hour",
              "what can I get done in 20 min",
          ])
    func recognisesPlanning(_ question: String) {
        #expect(FocusPlan.isPlanningQuestion(question))
    }

    @Test("questions about the screen are not planning",
          arguments: [
              "what does this function do",
              "How do I work on a branch in git?",
              "what is next to the save button",
          ])
    func leavesOtherQuestionsAlone(_ question: String) {
        #expect(!FocusPlan.isPlanningQuestion(question))
    }

    @Test("a stated budget is read in minutes",
          arguments: [
              ("I have 45 minutes", 45),
              ("got 20 min", 20),
              ("I have an hour", 60),
              ("half an hour free", 30),
              ("an hour and a half", 90),
              ("about 2 hours", 120),
              ("1.5 hours left", 90),
          ])
    func readsBudget(_ text: String, _ expected: Int) {
        #expect(FocusPlan.minutes(in: text) == expected)
    }

    @Test("no budget stated means none assumed")
    func noBudget() {
        #expect(FocusPlan.minutes(in: "what should I work on?") == nil)
    }

    @Test("with tasks, the model must choose among them and own its estimates")
    func noteConstrainsChoice() {
        let note = FocusPlan.note(minutes: 45, hasTasks: true, projectName: "Engram")
        #expect(note.contains("45 minutes"))
        #expect(note.contains("Choose only from the open tasks"))
        #expect(note.contains("estimate is yours"))
        #expect(note.contains("Engram"))
    }

    @Test("with no tasks linked, the model says so rather than inventing a list")
    func noteWithoutTasks() {
        let note = FocusPlan.note(minutes: 60, hasTasks: false, projectName: nil)
        #expect(note.contains("no open tasks"))
        #expect(note.contains("do not invent"))
    }

    @Test("the planning note sits directly ahead of the task list")
    func noteInPrompt() throws {
        var context = AskContext()
        context.tasks = ["- Ship the release (overdue, was due yesterday)"]
        context.planningNote = "PLANNING NOTE"
        let prompt = Prompt.user(question: "what should I work on", context: context)
        let note = try #require(prompt.range(of: "PLANNING NOTE"))
        let tasks = try #require(prompt.range(of: "Open tasks from the user's to-do app"))
        #expect(note.upperBound < tasks.lowerBound)
    }
}

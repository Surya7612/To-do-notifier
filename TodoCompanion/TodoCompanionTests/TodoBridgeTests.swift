import Foundation
import Testing
@testable import TodoCompanion

/// This parser reads a file another application owns. That app can add fields,
/// rename them, or write a half-flushed file, and none of that should take the
/// companion down or put a secret somewhere it does not belong.
@Suite("Reading the to-do app's data")
struct TodoBridgeTests {
    private func parse(_ json: String) -> LinkedWork {
        TodoBridge.parse(Data(json.utf8))
    }

    @Test("todos and notes are read")
    func readsTodosAndNotes() throws {
        let work = parse("""
        {
          "todos": [
            {"id": "1", "title": "Ship the test target", "status": "open", "dueAt": "2026-09-08T12:00:00.000Z"},
            {"id": "2", "title": "Renew certificate", "status": "done"}
          ],
          "notes": [
            {"id": "n1", "title": "Retrieval", "body": "structured beats semantic for now",
             "updatedAt": "2026-09-01T09:30:00.000Z"}
          ]
        }
        """)

        #expect(work.todos.count == 2)
        #expect(work.notes.count == 1)
        #expect(try #require(work.todos.first).title == "Ship the test target")
        #expect(try #require(work.notes.first).body == "structured beats semantic for now")
    }

    @Test("completed todos are marked done and left out of the open list")
    func separatesOpenFromDone() {
        let work = parse("""
        {"todos": [
          {"id": "1", "title": "open one", "status": "open"},
          {"id": "2", "title": "done one", "status": "done"}
        ]}
        """)

        #expect(work.openTodos.count == 1)
        #expect(work.openTodos.first?.title == "open one")
    }

    @Test("a past due date on an open todo reads as overdue, but not once it is done")
    func overdueOnlyAppliesToOpenWork() throws {
        let work = parse("""
        {"todos": [
          {"id": "1", "title": "late", "status": "open", "dueAt": "2020-01-01T00:00:00.000Z"},
          {"id": "2", "title": "late but finished", "status": "done", "dueAt": "2020-01-01T00:00:00.000Z"}
        ]}
        """)

        #expect(try #require(work.todos.first).isOverdue)
        #expect(try #require(work.todos.last).isOverdue == false)
    }

    @Test("dates parse with or without fractional seconds")
    func acceptsBothTimestampShapes() {
        let work = parse("""
        {"todos": [
          {"id": "1", "title": "fractional", "dueAt": "2026-09-08T12:00:00.000Z"},
          {"id": "2", "title": "plain", "dueAt": "2026-09-08T12:00:00Z"}
        ]}
        """)

        #expect(work.todos.count == 2)
        #expect(work.todos.allSatisfy { $0.dueAt != nil })
    }

    @Test("an unparseable date leaves the todo without one instead of dropping it")
    func badDateDoesNotDropTheTodo() throws {
        let work = parse(#"{"todos": [{"id": "1", "title": "keep me", "dueAt": "next tuesday"}]}"#)

        #expect(work.todos.count == 1)
        #expect(try #require(work.todos.first).dueAt == nil)
    }

    @Test("entries with no usable content are skipped")
    func skipsUnusableEntries() {
        let work = parse("""
        {
          "todos": [{"id": "1"}, {"title": "no id"}, {"id": "2", "title": ""}],
          "notes": [{"id": "n1", "title": "", "body": ""}, {"body": "body only"}]
        }
        """)

        #expect(work.todos.isEmpty, "a todo with no title has nothing to show the user")
        #expect(work.notes.isEmpty, "a note needs an id, and some text to be worth showing")
    }

    @Test("a note with only a body is still worth keeping")
    func bodyOnlyNoteIsKept() {
        let work = parse(#"{"notes": [{"id": "n1", "body": "just a thought"}]}"#)

        #expect(work.notes.count == 1)
        #expect(work.notes.first?.title.isEmpty == true)
    }

    @Test("unexpected field types are ignored rather than crashing")
    func survivesWrongTypes() {
        #expect(parse(#"{"todos": "not an array", "notes": 42}"#).isEmpty)
        #expect(parse(#"{"todos": [{"id": 5, "title": ["nested"]}]}"#).isEmpty)
    }

    @Test("truncated or empty files read as no work")
    func survivesGarbage() {
        #expect(parse("").isEmpty)
        #expect(parse("{").isEmpty)
        #expect(parse("[]").isEmpty)
        #expect(parse("null").isEmpty)
        #expect(parse("{}").isEmpty)
    }

    @Test("unknown fields the other app adds later are simply ignored")
    func toleratesUnknownFields()  {
        let work = parse("""
        {"schemaVersion": 7, "pet": {"mood": "happy"},
         "todos": [{"id": "1", "title": "still works", "colour": "blue", "subtasks": []}]}
        """)

        #expect(work.todos.count == 1)
    }

    @Test("quiet hours are read from the other app's settings")
    func readsQuietHours() {
        let work = parse("""
        {"settings": {"quietHoursEnabled": true, "quietHoursStart": 21, "quietHoursEnd": 8}}
        """)

        #expect(work.quietHours.isEnabled)
        #expect(work.quietHours.startHour == 21)
        #expect(work.quietHours.endHour == 8)
    }

    @Test("missing quiet-hours settings fall back to disabled, not to a guess")
    func quietHoursDefaultToOff() {
        #expect(parse("{}").quietHours.isEnabled == false)
        #expect(parse(#"{"settings": {}}"#).quietHours.isEnabled == false)
    }

    /// The Electron app keeps an OpenAI key in this same file. `LinkedWork`
    /// feeds the model prompt, so a key appearing anywhere in it would be one
    /// careless `joined()` away from being sent to a third party. Importing the
    /// key is a separate, explicit call.
    @Test("the API key in the same file never reaches the prompt data")
    func parsingNeverCarriesTheApiKey() {
        let secret = "sk-test-do-not-leak-me"
        let work = parse("""
        {"settings": {"openaiApiKey": "\(secret)"},
         "todos": [{"id": "1", "title": "a real task"}]}
        """)

        #expect(work.todos.count == 1)

        let everything = (work.todos.map(\.title) + work.notes.map { $0.title + $0.body })
            .joined(separator: " ")
        #expect(!everything.contains(secret))
    }
}

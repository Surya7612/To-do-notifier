import Foundation
import Testing
@testable import TodoCompanion

/// Half of a contract with `electron/lib/deepLink.cjs`, which nothing here
/// compiles against — so it asserts on the URL string the other app parses.
@Suite("Links into the To-Do Notifier")
@MainActor
struct ToDoAppLinkTests {
    @Test("a task link carries the full id, prefix and all, as a query item")
    func taskLink() throws {
        let url = try #require(ToDoApp.link(task: "companion:ABC-123"))
        #expect(url.scheme == "todonotifier")
        #expect(url.host == "task")
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.queryItems?.first { $0.name == "id" }?.value == "companion:ABC-123")
    }

    @Test("a project link names the project kind")
    func projectLink() throws {
        let url = try #require(ToDoApp.link(project: "P1"))
        #expect(url.absoluteString == "todonotifier://project?id=P1")
    }
}

import Foundation
import Testing
@testable import TodoCompanion

/// The published file is this app's half of a contract with a reader written in
/// another language, in another process, that nothing here compiles against.
/// A renamed key or a changed date format would not fail to build — it would
/// just make the to-do app stop showing project names, with no error anywhere.
/// So these tests assert on the encoded JSON rather than on the Swift types.
@Suite struct ProjectExportTests {
    private func project(named name: String, todoIDs: [String] = []) -> Project {
        let project = Project(name: name)
        project.linkedTodoIDs = todoIDs
        return project
    }

    @Test func carriesNameAndLinkedTasks() {
        let payload = ProjectExport.payload(for: [project(named: "Engram", todoIDs: ["t1", "t2"])])

        #expect(payload.projects.count == 1)
        #expect(payload.projects[0].name == "Engram")
        #expect(payload.projects[0].todoIDs == ["t1", "t2"])
    }

    @Test func identifierIsTheOneStoredInSettings() {
        let one = project(named: "Engram")
        let payload = ProjectExport.payload(for: [one])

        // The reader uses this to tell projects apart, and the panel uses the
        // same value to remember the current one. They have to agree.
        #expect(payload.projects[0].id == one.identifier)
    }

    @Test func sortsByNameSoTheOtherAppNeedNot() {
        let payload = ProjectExport.payload(for: [
            project(named: "Thesis"),
            project(named: "engram"),
            project(named: "Applications"),
        ])

        #expect(payload.projects.map(\.name) == ["Applications", "engram", "Thesis"])
    }

    @Test func emptyStoreStillPublishesAWellFormedFile() throws {
        // Deleting the last project has to leave a file saying so, not a stale
        // one still naming it.
        let data = try ProjectExport.encode(ProjectExport.payload(for: []))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(root["projects"] as? [Any] != nil)
        #expect((root["projects"] as? [Any])?.isEmpty == true)
    }

    /// Names the reader in `electron/lib/companionProjects.cjs` looks for.
    @Test func encodesTheKeysTheReaderLooksFor() throws {
        let payload = ProjectExport.payload(for: [project(named: "Engram", todoIDs: ["t1"])])
        let data = try ProjectExport.encode(payload)
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(root["version"] as? Int == ProjectExport.version)
        #expect(root["updatedAt"] as? String != nil)

        let projects = try #require(root["projects"] as? [[String: Any]])
        let first = try #require(projects.first)

        #expect(first["id"] as? String != nil)
        #expect(first["name"] as? String == "Engram")
        #expect(first["todoIDs"] as? [String] == ["t1"])
        #expect(first["savedContextCount"] as? Int == 0)
    }

    @Test func stampIsISO8601BecauseTheReaderIsJavaScript() throws {
        let moment = Date(timeIntervalSince1970: 1_757_289_600)
        let data = try ProjectExport.encode(ProjectExport.payload(for: [], now: moment))
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let stamp = try #require(root["updatedAt"] as? String)

        #expect(ISO8601DateFormatter().date(from: stamp) == moment)
    }

    @Test func normalizesTheNameItPublishes() {
        // The same collapsing the picker does, so the two apps never disagree
        // about what a project is called.
        let payload = ProjectExport.payload(for: [project(named: "  Engram   Notes ")])
        #expect(payload.projects[0].name == "Engram Notes")
    }

    @Test func writesInsideThisAppsOwnContainer() {
        // Anywhere else needs a second file prompt from the user, and the
        // sandbox would refuse the write besides.
        #expect(ProjectExport.location.lastPathComponent == ProjectExport.fileName)
        #expect(ProjectExport.location.path.contains("Application Support"))
    }
}

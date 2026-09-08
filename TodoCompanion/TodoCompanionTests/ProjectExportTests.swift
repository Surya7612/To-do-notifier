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

    // MARK: - Reminders offered as tasks

    private func reminder(_ intent: String, dueIn seconds: TimeInterval) -> SavedContext {
        let record = SavedContext(intent: intent, imageData: Data(), sourceApp: "Cursor")
        record.remindAt = Date().addingTimeInterval(seconds)
        return record
    }

    @Test func offersAPendingReminderAsATask() throws {
        let record = reminder("Text voice bugs", dueIn: 3_600)
        let payload = ProjectExport.payload(for: [], pendingReminders: [record])

        let request = try #require(payload.requestedTasks.first)
        // The id has to be the reminder's own, since the importer keys on it to
        // avoid creating the same task twice.
        #expect(request.id == record.reminderIdentifier)
        #expect(request.title == "Text voice bugs")
    }

    @Test func titleIsTheUsersWordsNotASummary() throws {
        let record = reminder("Text voice bugs", dueIn: 3_600)
        record.aiSummary = "The user is tracking issues with speech input."
        let payload = ProjectExport.payload(for: [], pendingReminders: [record])

        // This becomes a row in a list of things the user said they would do.
        // A model's gloss standing in for their own words there is the exact
        // confusion the whole app exists to prevent.
        #expect(payload.requestedTasks.first?.title == "Text voice bugs")
    }

    @Test func aFiredReminderIsNoLongerOffered() {
        // Publishing one already past would ask the other app to create a task
        // that was due yesterday — and, being keyed on a stable id, it would
        // then keep it forever.
        let payload = ProjectExport.payload(for: [], pendingReminders: [
            reminder("Already happened", dueIn: -3_600),
        ])

        #expect(payload.requestedTasks.isEmpty)
    }

    @Test func aSaveWithNoReminderIsNotATask() {
        // Most saves are just kept material. Only an armed reminder is the
        // user saying they want to come back to something.
        let record = SavedContext(intent: "Just keeping this", imageData: Data(), sourceApp: "Safari")
        let payload = ProjectExport.payload(for: [], pendingReminders: [record])

        #expect(payload.requestedTasks.isEmpty)
    }

    @Test func aFiledReminderJoinsItsProjectsTaskList() throws {
        // So a task created from the reminder carries the project's label in
        // the other app, through the labelling that already exists there rather
        // than through anything new on that side.
        let one = project(named: "Engram", todoIDs: ["t1"])
        let record = reminder("Text voice bugs", dueIn: 3_600)
        record.project = one

        let payload = ProjectExport.payload(for: [one], pendingReminders: [record])
        let published = try #require(payload.projects.first)

        #expect(published.todoIDs == ["t1", "companion:\(record.reminderIdentifier)"])
    }

    @Test func anUnfiledReminderJoinsNoProject() {
        let one = project(named: "Engram", todoIDs: ["t1"])
        let payload = ProjectExport.payload(
            for: [one],
            pendingReminders: [reminder("Text voice bugs", dueIn: 3_600)]
        )

        #expect(payload.projects.first?.todoIDs == ["t1"])
    }

    @Test func offeredTasksEncodeTheKeysTheImporterReads() throws {
        let record = reminder("Text voice bugs", dueIn: 3_600)
        let data = try ProjectExport.encode(
            ProjectExport.payload(for: [], pendingReminders: [record])
        )
        let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let tasks = try #require(root["requestedTasks"] as? [[String: Any]])
        let first = try #require(tasks.first)

        #expect(first["id"] as? String == record.reminderIdentifier)
        #expect(first["title"] as? String == "Text voice bugs")

        // The importer rejects a date it cannot parse, so this is the field
        // most likely to break the contract silently.
        let dueAt = try #require(first["dueAt"] as? String)
        #expect(ISO8601DateFormatter().date(from: dueAt) != nil)
    }

    @Test func readsBackWhichRemindersTheOtherAppTookOver() {
        // How this app learns it can stop notifying for one.
        let adopted = ProjectExport.adoptedReminderIdentifiers(inTodoIDs: [
            "companion:abc",
            "companion:def",
            "an-ordinary-task",
            "companion:",
        ])

        #expect(adopted == ["abc", "def"])
    }

    @Test func aTaskThisAppNeverAskedForIsNotAHandOver() {
        // Cancelling on a loose prefix match would silence a reminder the other
        // app knows nothing about.
        #expect(ProjectExport.adoptedReminderIdentifiers(inTodoIDs: ["abc", ""]).isEmpty)
    }

    @Test func theImportPrefixMatchesTheOtherApp() {
        // Mirrored in electron/lib/companionTasks.cjs. If these drift, this app
        // stops recognising a hand-over and every reminder fires twice.
        #expect(ProjectExport.importedTaskPrefix == "companion:")
    }

    @Test func writesInsideThisAppsOwnContainer() {
        // Anywhere else needs a second file prompt from the user, and the
        // sandbox would refuse the write besides.
        #expect(ProjectExport.location.lastPathComponent == ProjectExport.fileName)
        #expect(ProjectExport.location.path.contains("Application Support"))
    }
}

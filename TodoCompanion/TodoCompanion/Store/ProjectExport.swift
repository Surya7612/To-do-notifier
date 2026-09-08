import Foundation
import SwiftData

/// Publishes the project list to a file the To-Do Notifier can read.
///
/// The direction is the only one available. A project groups saved screen
/// contexts, which the to-do app knows nothing about, so it cannot own the
/// list; and writing a project field into `app-data.json` would make this app a
/// writer of a file another app owns, with no locking between them. So each app
/// owns one file and reads the other's: `TodoBridge` reads tasks in, this writes
/// the grouping out.
///
/// It lands in this app's own container because the sandbox permits nowhere
/// else without another file prompt. The to-do app is not sandboxed and reads
/// it there directly.
enum ProjectExport {
    static let fileName = "companion-projects.json"

    /// What the to-do app prefixes onto a task it created from a request.
    ///
    /// Part of the contract rather than that app's private business. This app
    /// derives the same id to put in a project's published task list, and the
    /// other app matches on it to leave the announcing to this one. Mirrored in
    /// `electron/lib/companionTasks.cjs`; if the two drift, one reminder is
    /// announced twice.
    static let importedTaskPrefix = "companion:"

    /// How long a reminder keeps being offered after its time has passed.
    ///
    /// Not zero, which is what it effectively was before, and that was a real
    /// bug for short reminders: "remind me in one minute" dropped out of the
    /// export a minute later, so unless the to-do app happened to be opened
    /// inside that minute the task was never created at all. A fired reminder
    /// is still worth offering — an overdue task is precisely what the other
    /// app is good at putting in front of someone.
    ///
    /// Bounded rather than indefinite, because the import keys on a stable id:
    /// a task deleted over there would otherwise return on every launch for
    /// good.
    static let offerWindowAfterDue: TimeInterval = 7 * 24 * 60 * 60

    /// Bumped only for a change a reader could not survive. The to-do app is
    /// written to ignore fields it does not recognize, so adding one is not
    /// such a change.
    static let version = 1

    struct Payload: Codable, Equatable {
        var version: Int
        var updatedAt: Date
        var projects: [Entry]
        /// Reminders the user set here, offered to the app that owns tasks.
        var requestedTasks: [TaskRequest] = []
    }

    /// A reminder, published so the to-do app can make a task of it.
    ///
    /// Offered rather than written: this app cannot create a task, because
    /// `app-data.json` belongs to a process that holds it in memory and
    /// rewrites it whole. So the same rule that governs file edits governs
    /// this — Max proposes, the owner writes. The to-do app reads these and
    /// creates tasks of its own, which is what makes them completable there.
    struct TaskRequest: Codable, Equatable {
        /// `SavedContext.reminderIdentifier`, which is stable across launches
        /// and store migrations. The importer keys on it to stay idempotent,
        /// so this must never be regenerated for an existing reminder.
        var id: String

        /// The user's own stated reason, verbatim.
        ///
        /// Never `aiSummary`: this becomes a row in a list of things the user
        /// said they would do, and a model's gloss standing in for their words
        /// there is the exact confusion this app exists to prevent.
        var title: String

        var dueAt: Date
    }

    struct Entry: Codable, Equatable {
        var id: String
        var name: String
        /// The to-do app's own task identifiers, which is the whole point of
        /// the file: it can resolve these against tasks it already has.
        ///
        /// Includes the ids the *imported* reminders will have, which are
        /// derivable because they are the prefix and the reminder's own
        /// identifier. That is what makes a task created from a reminder carry
        /// its project's label over there, without the importer needing to know
        /// anything about projects. An id whose task has not been created yet
        /// simply does not resolve, which is already the ordinary case for a
        /// task deleted in that app.
        var todoIDs: [String]
        var savedContextCount: Int
    }

    /// Resolves inside this app's container, which is the only place it can
    /// write without asking.
    static var location: URL {
        URL.applicationSupportDirectory.appending(path: fileName)
    }

    static func payload(for projects: [Project],
                        pendingReminders: [SavedContext] = [],
                        now: Date = Date()) -> Payload {
        let stillOffered = now.addingTimeInterval(-offerWindowAfterDue)
        let offered = pendingReminders.filter { record in
            guard let dueAt = record.remindAt, dueAt > stillOffered else { return false }
            return !record.intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return Payload(
            version: version,
            updatedAt: now,
            projects: projects
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { project in
                    let fromReminders = offered
                        .filter { $0.project?.identifier == project.identifier }
                        .map { importedTaskPrefix + $0.reminderIdentifier }

                    return Entry(id: project.identifier,
                                 name: project.name,
                                 todoIDs: project.linkedTodoIDs + fromReminders,
                                 savedContextCount: project.contexts.count)
                },
            requestedTasks: offered
                .map { record in
                    TaskRequest(
                        id: record.reminderIdentifier,
                        title: record.intent.trimmingCharacters(in: .whitespacesAndNewlines),
                        dueAt: record.remindAt ?? now
                    )
                }
                .sorted { $0.dueAt < $1.dueAt }
        )
    }

    /// Which of these to-do app task ids came from a reminder set here.
    ///
    /// Reads the id scheme back the other way. Used when Apple Reminders has
    /// taken on announcing a task, so this app can stop announcing it too —
    /// a prefix match rather than a loose `contains`, or an unrelated task
    /// happening to carry the word would silence a reminder Apple never got.
    static func reminderIdentifiers(inTaskIDs identifiers: [String]) -> [String] {
        identifiers.compactMap { identifier in
            guard identifier.hasPrefix(importedTaskPrefix) else { return nil }
            let reminderIdentifier = String(identifier.dropFirst(importedTaskPrefix.count))
            return reminderIdentifier.isEmpty ? nil : reminderIdentifier
        }
    }

    static func encode(_ payload: Payload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    /// Rewrites the file from whatever is in the store.
    ///
    /// Republishing everything rather than patching one project keeps the file
    /// from drifting: there is no sequence of edits that leaves it describing a
    /// state the store was never in.
    static func publish(from context: ModelContext, now: Date = Date()) {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name)])
        guard let projects = try? context.fetch(descriptor) else { return }

        // Filtered here rather than in the fetch because a predicate over an
        // optional date is the kind of thing SwiftData translates differently
        // between releases, and getting it wrong publishes an empty list.
        let reminders = (try? context.fetch(FetchDescriptor<SavedContext>()))?
            .filter { $0.remindAt != nil } ?? []

        write(payload(for: projects, pendingReminders: reminders, now: now))
    }

    static func write(_ payload: Payload) {
        do {
            let directory = location.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            // Atomic because the reader is another process polling on its own
            // schedule; a torn write would show up there as corrupt JSON.
            try encode(payload).write(to: location, options: .atomic)
        } catch {
            // A failure here costs the other app a label, not this app a save.
            NSLog("[ProjectExport] couldn't write \(location.path): \(error)")
        }
    }
}

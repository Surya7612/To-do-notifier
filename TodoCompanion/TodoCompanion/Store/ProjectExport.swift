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

    /// Bumped only for a change a reader could not survive. The to-do app is
    /// written to ignore fields it does not recognize, so adding one is not
    /// such a change.
    static let version = 1

    struct Payload: Codable, Equatable {
        var version: Int
        var updatedAt: Date
        var projects: [Entry]
    }

    struct Entry: Codable, Equatable {
        var id: String
        var name: String
        /// The to-do app's own task identifiers, which is the whole point of
        /// the file: it can resolve these against tasks it already has.
        var todoIDs: [String]
        var savedContextCount: Int
    }

    /// Resolves inside this app's container, which is the only place it can
    /// write without asking.
    static var location: URL {
        URL.applicationSupportDirectory.appending(path: fileName)
    }

    static func payload(for projects: [Project], now: Date = Date()) -> Payload {
        Payload(
            version: version,
            updatedAt: now,
            projects: projects
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .map { project in
                    Entry(id: project.identifier,
                          name: project.name,
                          todoIDs: project.linkedTodoIDs,
                          savedContextCount: project.contexts.count)
                }
        )
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
        write(payload(for: projects, now: now))
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

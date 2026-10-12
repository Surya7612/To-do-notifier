import AppKit
import Foundation
import UniformTypeIdentifiers

/// One open task from the Electron To-Do Notifier.
struct LinkedTodo: Identifiable, Hashable {
    let id: String
    let title: String
    let dueAt: Date?
    let isDone: Bool

    var isOverdue: Bool {
        guard let dueAt, !isDone else { return false }
        return dueAt < Date()
    }
}

/// One note from the Electron app.
struct LinkedNote: Identifiable, Hashable {
    let id: String
    let title: String
    let body: String
    let updatedAt: Date
}

/// The hours the user already told the other app not to disturb them.
///
/// Mirrored rather than reinvented: they configured this once, in the app that
/// owns notification preferences, and a second reminder system that ignored it
/// would make the setting a lie.
/// Nonisolated for the same reason `ReminderPhrase` is: it is a value type with
/// pure functions, and the module defaults to `MainActor`, which would
/// otherwise make even constructing one a main-actor call.
nonisolated struct QuietHours: Equatable, Sendable {
    var isEnabled = false
    var startHour = 22
    var endHour = 7

    /// Matches `inQuietHours` in `electron/lib/dataMerge.cjs`, including its
    /// treatment of an equal start and end as "never quiet" rather than
    /// "always quiet".
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled, startHour != endHour else { return false }

        let hour = calendar.component(.hour, from: date)
        return startHour < endHour
            ? hour >= startHour && hour < endHour
            : hour >= startHour || hour < endHour
    }

    /// The first moment at or after `date` that is not inside quiet hours.
    func firstMomentAfter(_ date: Date, calendar: Calendar = .current) -> Date {
        guard contains(date, calendar: calendar) else { return date }

        // Quiet hours are whole hours, so the end boundary is always reachable
        // by advancing to the next occurrence of endHour.
        var candidate = calendar.date(bySettingHour: endHour, minute: 0, second: 0, of: date) ?? date
        if candidate <= date {
            candidate = calendar.date(byAdding: .day, value: 1, to: candidate) ?? candidate
        }
        return candidate
    }
}

struct LinkedWork {
    var todos: [LinkedTodo] = []
    var notes: [LinkedNote] = []
    var quietHours = QuietHours()

    var isEmpty: Bool { todos.isEmpty && notes.isEmpty }
    var openTodos: [LinkedTodo] { todos.filter { !$0.isDone } }

    func todos(withIDs identifiers: [String]) -> [LinkedTodo] {
        // Preserves the todo app's own ordering, and quietly skips anything
        // deleted over there since it was linked.
        let wanted = Set(identifiers)
        return todos.filter { wanted.contains($0.id) }
    }
}

/// Reads the Electron app's `app-data.json` so the companion can answer using
/// the tasks and notes the user already keeps.
///
/// The two apps stayed strangers until now: the plan always described one
/// personal context system, but nothing in the native app had ever read the
/// other's data.
///
/// Access goes through a security-scoped bookmark rather than a hardcoded path.
/// This app is sandboxed and cannot reach `~/Library/Application Support` on its
/// own, and the alternative — turning the sandbox off — would trade a real
/// protection for the convenience of skipping one file picker.
@MainActor
enum TodoBridge {
    private static let bookmarkKey = "electronDataBookmark"

    /// Where the Electron app keeps its store, used only to point the open
    /// panel somewhere useful.
    ///
    /// Built from the real home directory rather than `URL.applicationSupportDirectory`,
    /// which inside a sandbox resolves to this app's own container — a place the
    /// Electron app has never written to.
    static var suggestedLocation: URL {
        let home = getpwuid(getuid())
            .flatMap { String(validatingCString: $0.pointee.pw_dir) }
            .map(URL.init(fileURLWithPath:))
            ?? URL.homeDirectory

        return home.appending(path: "Library/Application Support/todo-notifier/app-data.json")
    }

    /// The folder holding `app-data.json`, which is what the link now grants.
    ///
    /// A folder rather than the file because reminders have to reach the
    /// to-do app, and the only route left is a file beside its store: macOS
    /// refuses that app reading this one's container (`EPERM`, logged by the
    /// kernel as a sandbox deny), and a bookmark to `app-data.json` grants that
    /// one file — writing a sibling with it fails with Cocoa error 513. The
    /// folder grant covers both. This app still never writes `app-data.json`.
    private static let folderBookmarkKey = "electronDataFolderBookmark"
    private static let dataFileName = "app-data.json"

    static var isLinked: Bool {
        UserDefaults.standard.data(forKey: folderBookmarkKey) != nil
            || UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// Linked the old way, to the file alone: tasks are readable, but nothing
    /// set here can become a task over there until the folder is chosen.
    static var needsFolderLink: Bool {
        UserDefaults.standard.data(forKey: folderBookmarkKey) == nil
            && UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// Why the last link attempt was refused, for Settings to say.
    private(set) static var linkProblem: String?

    /// Asks the user to choose the folder once. Their choice is what grants
    /// the sandbox access, so this cannot be done silently.
    static func link() -> Bool {
        linkProblem = nil
        let chosen = FilePicker.choose { panel in
            panel.title = "Choose your To-Do Notifier folder"
            panel.message = "This is the todo-notifier folder that holds app-data.json — click Open. Max reads your tasks from it and leaves reminders beside it; it never edits app-data.json."
            panel.prompt = "Open"
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.directoryURL = suggestedLocation.deletingLastPathComponent()
            // ~/Library is hidden in Finder, and this folder lives inside it.
            panel.showsHiddenFiles = true
        }
        guard let folder = chosen else { return false }

        guard folder.startAccessingSecurityScopedResource() else {
            linkProblem = "macOS did not grant access to that folder."
            return false
        }
        defer { folder.stopAccessingSecurityScopedResource() }

        guard FileManager.default.fileExists(atPath: folder.appending(path: dataFileName).path) else {
            linkProblem = "That folder has no app-data.json. Choose the todo-notifier folder."
            return false
        }

        do {
            let bookmark = try folder.bookmarkData(options: .withSecurityScope,
                                                   includingResourceValuesForKeys: nil,
                                                   relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: folderBookmarkKey)
            UserDefaults.standard.removeObject(forKey: bookmarkKey)
            cached = nil
            resolvedGrant = nil
            return true
        } catch {
            linkProblem = "Could not remember that folder: \(error.localizedDescription)"
            NSLog("[TodoBridge] couldn't bookmark \(folder.path): \(error)")
            return false
        }
    }

    static func unlink() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: folderBookmarkKey)
        cached = nil
        resolvedGrant = nil
    }

    /// What the link resolves to: the URL whose access has to be started, and
    /// the store inside it.
    private struct Grant {
        let bookmark: Data
        let scope: URL
        let dataFile: URL
        let isFolder: Bool
    }

    private static var resolvedGrant: Grant?

    private static func grant() -> Grant? {
        let key: String
        let isFolder: Bool
        if UserDefaults.standard.data(forKey: folderBookmarkKey) != nil {
            key = folderBookmarkKey
            isFolder = true
        } else {
            key = bookmarkKey
            isFolder = false
        }
        guard let bookmark = UserDefaults.standard.data(forKey: key) else {
            resolvedGrant = nil
            return nil
        }
        if let resolvedGrant, resolvedGrant.bookmark == bookmark { return resolvedGrant }

        guard let url = SecurityScopedBookmark.resolve(bookmark, persist: { fresh in
            UserDefaults.standard.set(fresh, forKey: key)
        }) else { return nil }

        // Keyed on the blob as read, so a stale-refresh rewrite resolves once
        // more and is then cached under the new blob.
        let resolved = Grant(bookmark: bookmark,
                             scope: url,
                             dataFile: isFolder ? url.appending(path: dataFileName) : url,
                             isFolder: isFolder)
        resolvedGrant = resolved
        return resolved
    }

    /// Drops `companion-projects.json` beside the linked `app-data.json`.
    ///
    /// Returns false when there is no folder grant, which is the state a
    /// file-only link from an older build is in.
    @discardableResult
    static func publishCompanionProjects(_ data: Data) -> Bool {
        guard let grant = grant(), grant.isFolder,
              grant.scope.startAccessingSecurityScopedResource()
        else { return false }
        defer { grant.scope.stopAccessingSecurityScopedResource() }

        let destination = grant.scope.appending(path: ProjectExport.fileName)
        if let existing = try? Data(contentsOf: destination), existing == data { return true }
        do {
            try data.write(to: destination, options: .atomic)
            return true
        } catch {
            NSLog("[TodoBridge] couldn't publish \(destination.path): \(error)")
            return false
        }
    }

    /// The last parse, keyed on the bookmark and the file's modification date
    /// and size. `load` runs on every capture, on the main actor, before
    /// "Reading your screen…" clears — re-reading and re-parsing a file the
    /// other app had not touched was pure delay on every summon.
    private static var cached: (bookmark: Data, stamp: FileStamp, work: LinkedWork)?

    private struct FileStamp: Equatable {
        var modified: Date?
        var size: Int?
    }

    static func load() -> LinkedWork {
        guard let grant = grant() else {
            cached = nil
            return LinkedWork()
        }

        guard grant.scope.startAccessingSecurityScopedResource() else { return LinkedWork() }
        defer { grant.scope.stopAccessingSecurityScopedResource() }

        let url = grant.dataFile
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let stamp = FileStamp(modified: values?.contentModificationDate, size: values?.fileSize)
        if let cached, cached.bookmark == grant.bookmark, cached.stamp == stamp, stamp.modified != nil {
            return cached.work
        }

        guard let data = try? Data(contentsOf: url) else { return LinkedWork() }
        let work = parse(data)
        cached = (grant.bookmark, stamp, work)
        return work
    }

    /// Reads the OpenAI key the Electron app stores in the same file.
    ///
    /// Deliberately not part of `LinkedWork`: that struct feeds the prompt, and
    /// a secret must never be one careless `joined()` away from being sent to a
    /// model. It is also never read implicitly — the settings screen offers an
    /// explicit import, because the user handed that key to another app for
    /// transcription and reusing it here is their call, not ours.
    static func importableOpenAIKey() -> String? {
        guard let grant = grant(),
              grant.scope.startAccessingSecurityScopedResource()
        else { return nil }
        defer { grant.scope.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: grant.dataFile),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let settings = root["settings"] as? [String: Any],
              let key = (settings["openaiApiKey"] as? String)?
                  .trimmingCharacters(in: .whitespacesAndNewlines),
              !key.isEmpty
        else { return nil }

        return key
    }

    static func parse(_ data: Data) -> LinkedWork {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return LinkedWork()
        }

        let stamps = ISO8601DateFormatter()
        stamps.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        func date(_ value: Any?) -> Date? {
            guard let raw = value as? String, !raw.isEmpty else { return nil }
            return stamps.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
        }

        let todos = (root["todos"] as? [[String: Any]] ?? []).compactMap { item -> LinkedTodo? in
            guard let id = item["id"] as? String,
                  let title = item["title"] as? String, !title.isEmpty
            else { return nil }
            return LinkedTodo(id: id,
                              title: title,
                              dueAt: date(item["dueAt"]),
                              isDone: (item["status"] as? String) == "done")
        }

        let notes = (root["notes"] as? [[String: Any]] ?? []).compactMap { item -> LinkedNote? in
            guard let id = item["id"] as? String else { return nil }
            let title = item["title"] as? String ?? ""
            let body = item["body"] as? String ?? ""
            guard !title.isEmpty || !body.isEmpty else { return nil }
            return LinkedNote(id: id,
                              title: title,
                              body: body,
                              updatedAt: date(item["updatedAt"]) ?? .distantPast)
        }

        return LinkedWork(todos: todos, notes: notes, quietHours: quietHours(in: root))
    }

    /// Only the do-not-disturb window is read out of `settings`. The rest of
    /// that dictionary is the other app's business, and one of its keys is an
    /// API key that must never end up near prompt data.
    private static func quietHours(in root: [String: Any]) -> QuietHours {
        guard let settings = root["settings"] as? [String: Any] else { return QuietHours() }

        var hours = QuietHours()
        hours.isEnabled = settings["quietHoursEnabled"] as? Bool ?? false
        if let start = settings["quietHoursStart"] as? Int { hours.startHour = start }
        if let end = settings["quietHoursEnd"] as? Int { hours.endHour = end }
        return hours
    }
}

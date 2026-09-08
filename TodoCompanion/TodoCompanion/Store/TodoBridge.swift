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
struct QuietHours: Equatable, Sendable {
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

    static var isLinked: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// Asks the user to point at the file once. Their choice is what grants the
    /// sandbox access, so this cannot be done silently.
    static func link() -> Bool {
        let panel = NSOpenPanel()
        panel.title = "Choose your To-Do Notifier data"
        panel.message = "Pick app-data.json so the companion can see your tasks and notes."
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = suggestedLocation.deletingLastPathComponent()
        // ~/Library is hidden in Finder, and this file lives inside it.
        panel.showsHiddenFiles = true

        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return false }

        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            return true
        } catch {
            NSLog("[TodoBridge] couldn't bookmark \(url.path): \(error)")
            return false
        }
    }

    static func unlink() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    static func load() -> LinkedWork {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return LinkedWork() }

        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale)
        else { return LinkedWork() }

        guard url.startAccessingSecurityScopedResource() else { return LinkedWork() }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else { return LinkedWork() }
        return parse(data)
    }

    /// Reads the OpenAI key the Electron app stores in the same file.
    ///
    /// Deliberately not part of `LinkedWork`: that struct feeds the prompt, and
    /// a secret must never be one careless `joined()` away from being sent to a
    /// model. It is also never read implicitly — the settings screen offers an
    /// explicit import, because the user handed that key to another app for
    /// transcription and reusing it here is their call, not ours.
    static func importableOpenAIKey() -> String? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }

        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource()
        else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url),
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

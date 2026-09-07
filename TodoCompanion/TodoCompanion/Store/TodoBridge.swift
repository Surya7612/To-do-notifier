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

struct LinkedWork {
    var todos: [LinkedTodo] = []
    var notes: [LinkedNote] = []

    var isEmpty: Bool { todos.isEmpty && notes.isEmpty }
    var openTodos: [LinkedTodo] { todos.filter { !$0.isDone } }
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

        return LinkedWork(todos: todos, notes: notes)
    }
}

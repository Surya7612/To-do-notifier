import AppKit

/// Sends the user to the To-Do Notifier at a task or a project.
///
/// Completing a task belongs to that app, so this one never offers a checkbox
/// that would have to write `app-data.json`. What it can do is remove the
/// hunt: a link opens that app's window at the row in question. A URL rather
/// than anything shared, because it is the one thing macOS routes between two
/// unrelated processes — and it launches the other app if it is not running.
enum ToDoApp {
    static let bundleIdentifier = "com.surya.todonotifier"

    static func link(task id: String) -> URL? { link(kind: "task", id: id) }
    static func link(project id: String) -> URL? { link(kind: "project", id: id) }

    nonisolated static func link(kind: String, id: String) -> URL? {
        var components = URLComponents()
        components.scheme = "todonotifier"
        components.host = kind
        components.queryItems = [URLQueryItem(name: "id", value: id)]
        return components.url
    }

    /// Whether the other app is installed at all, so a button that could only
    /// fail is not offered.
    static var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) != nil
    }

    static func showTask(_ id: String) { open(link(task: id)) }
    static func showProject(_ id: String) { open(link(project: id)) }

    /// An older build of the other app predates the link, so macOS has no
    /// handler for it; opening the app plainly is still most of the way there.
    private static func open(_ url: URL?) {
        if let url, NSWorkspace.shared.urlForApplication(toOpen: url) != nil {
            NSWorkspace.shared.open(url)
            return
        }
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return }
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }
}

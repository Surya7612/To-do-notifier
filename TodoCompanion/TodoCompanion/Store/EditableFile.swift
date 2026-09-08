import AppKit
import Foundation

/// One file the user opened so Max can propose a change to it.
///
/// Scope is deliberately one file at a time, chosen through a picker. The plan
/// rejects an autonomous computer-use agent, and this is the opposite of one:
/// the model may only ever *propose*, the user is shown a diff, and nothing
/// reaches disk without them pressing Apply. It is the same rule the reminder
/// parser follows — inference may suggest, not act.
///
/// A whole-project agent was the alternative and is a worse product, not merely
/// a riskier one: this app sees a screenshot, has no file tree, and cannot run
/// the tests. The editor the user already has open does all of that better. The
/// value here is being able to ask about the thing on screen and get a concrete
/// change back, without leaving what they were doing.
@MainActor
@Observable
final class EditableFile {
    private(set) var name = ""
    private(set) var contents = ""
    private(set) var isOpen = false

    /// The contents as they were when opened, so an applied change can be put
    /// back within the session. Not a substitute for version control, and the
    /// UI says as much.
    private var originalContents: String?
    private(set) var canRevert = false

    private var bookmark: Data?

    /// Asks the user which file, then reads it.
    ///
    /// Read-write access comes from them choosing it; there is no way to reach
    /// a file the user has not pointed at, which is the property that makes
    /// this safe to ship at all.
    func open() -> Bool {
        guard let url = FilePicker.choose({ panel in
            panel.title = "Choose a file to work on"
            panel.message = "Max can propose changes to this one file. You will see a diff before anything is written."
            panel.canChooseDirectories = false
            panel.allowsMultipleSelection = false
            panel.showsHiddenFiles = true
        }) else { return false }

        do {
            let data = try Data(contentsOf: url)
            // Refused rather than force-decoded: writing a lossy conversion
            // back over someone's file would corrupt it silently.
            guard let text = String(data: data, encoding: .utf8) else {
                NSLog("[EditableFile] \(url.lastPathComponent) is not UTF-8")
                return false
            }

            bookmark = try url.bookmarkData(options: .withSecurityScope,
                                            includingResourceValuesForKeys: nil,
                                            relativeTo: nil)
            name = url.lastPathComponent
            contents = text
            originalContents = nil
            canRevert = false
            isOpen = true
            return true
        } catch {
            NSLog("[EditableFile] couldn't open \(url.path): \(error)")
            return false
        }
    }

    func close() {
        bookmark = nil
        name = ""
        contents = ""
        originalContents = nil
        canRevert = false
        isOpen = false
    }

    var context: EditableFileContext? {
        isOpen ? EditableFileContext(name: name, contents: contents) : nil
    }

    /// Writes the proposed contents, having been told to by the user.
    @discardableResult
    func apply(_ proposed: String) -> Bool {
        let previous = contents
        guard write(proposed) else { return false }

        // Only the first apply records a revert point, so reverting always
        // returns to the file as it was before this conversation touched it
        // rather than undoing one step of several.
        if originalContents == nil { originalContents = previous }
        contents = proposed
        canRevert = true
        return true
    }

    @discardableResult
    func revert() -> Bool {
        guard let originalContents, write(originalContents) else { return false }

        contents = originalContents
        self.originalContents = nil
        canRevert = false
        return true
    }

    private func write(_ text: String) -> Bool {
        guard let bookmark else { return false }

        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource()
        else { return false }
        defer { url.stopAccessingSecurityScopedResource() }

        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("[EditableFile] couldn't write \(url.path): \(error)")
            return false
        }
    }
}

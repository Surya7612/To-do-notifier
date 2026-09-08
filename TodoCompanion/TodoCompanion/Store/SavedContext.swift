import Foundation
import SwiftData

/// A named bucket a saved context can belong to.
///
/// Deliberately just a name. A project here is a thing the user is working on,
/// not a schema — anything more structured would be guessing at how they think
/// about their own work.
@Model
final class Project {
    var name: String = ""
    var createdAt: Date = Date()

    /// Stable string identity, for remembering the chosen project in
    /// `UserDefaults` across launches. `persistentModelID` has no durable
    /// string form to store.
    var identifier: String = UUID().uuidString

    @Relationship(deleteRule: .nullify, inverse: \SavedContext.project)
    var contexts: [SavedContext] = []

    /// Tasks from the To-Do Notifier that belong to this project.
    ///
    /// Stored as that app's own identifiers, on this side of the boundary. The
    /// grouping is this app's idea, so this app keeps it; writing a project
    /// field back into `app-data.json` would make the companion a writer of a
    /// file it does not own. A task deleted over there simply stops resolving.
    var linkedTodoIDs: [String] = []

    init(name: String) {
        self.name = Self.normalize(name)
        self.createdAt = Date()
        self.identifier = UUID().uuidString
    }

    /// Collapses whitespace so "  Engram " and "Engram" are not two projects
    /// the user has to keep straight.
    nonisolated static func normalize(_ name: String) -> String {
        name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

/// One captured thing plus the reason it mattered.
///
/// `intent` and `aiSummary` are deliberately separate fields: the user's own
/// words are authoritative and the model's interpretation must never be
/// displayed as though the user wrote it.
@Model
final class SavedContext {
    var createdAt: Date = Date()

    /// The user's own explanation. Never overwritten by inference.
    var intent: String = ""

    /// Model-generated gloss. Always presented as such.
    var aiSummary: String = ""

    var recognizedText: String = ""

    @Attribute(.externalStorage)
    var imageData: Data?

    // Provenance
    var sourceApp: String = ""
    var windowTitle: String = ""

    var topics: [String] = []
    var project: Project?

    /// When the user asked to be brought back to this. Nil means no reminder.
    var remindAt: Date?

    /// Identifier for the pending notification.
    ///
    /// A separate stored value rather than `persistentModelID`, which has no
    /// stable string form to hand `UNNotificationRequest` and would change
    /// under a store migration — leaving a scheduled reminder no longer
    /// cancellable.
    var reminderIdentifier: String = UUID().uuidString

    var hasPendingReminder: Bool {
        guard let remindAt else { return false }
        return remindAt > Date()
    }

    init(intent: String,
         recognizedText: String = "",
         imageData: Data? = nil,
         sourceApp: String = "",
         windowTitle: String = "",
         topics: [String] = []) {
        self.createdAt = Date()
        self.intent = intent
        self.recognizedText = recognizedText
        self.imageData = imageData
        self.sourceApp = sourceApp
        self.windowTitle = windowTitle
        self.topics = topics
    }

    var provenanceLabel: String {
        switch (sourceApp.isEmpty, windowTitle.isEmpty) {
        case (false, false): "\(sourceApp) — \(windowTitle)"
        case (false, true): sourceApp
        default: "Unknown source"
        }
    }

    /// Everything a plain-text search should look through.
    var searchHaystack: String {
        [intent, aiSummary, sourceApp, windowTitle, topics.joined(separator: " "), recognizedText]
            .joined(separator: "\n")
    }
}

extension String {
    /// Pulls `#tag` markers out of the user's own sentence so tagging costs no
    /// extra interaction, and returns the sentence with them removed.
    func splittingHashtags() -> (text: String, topics: [String]) {
        var topics: [String] = []
        var words: [String] = []

        for word in split(separator: " ", omittingEmptySubsequences: true) {
            if word.hasPrefix("#"), word.count > 1 {
                let tag = word.dropFirst().trimmingCharacters(in: .punctuationCharacters)
                if !tag.isEmpty { topics.append(tag.lowercased()) }
            } else {
                words.append(String(word))
            }
        }

        let cleaned = words.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return (cleaned.isEmpty ? self : cleaned, topics)
    }
}

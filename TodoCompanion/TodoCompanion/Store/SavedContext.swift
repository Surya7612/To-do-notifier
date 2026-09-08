import Foundation
import SwiftData

/// A named bucket a saved context can belong to.
@Model
final class Project {
    var name: String = ""
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \SavedContext.project)
    var contexts: [SavedContext] = []

    init(name: String) {
        self.name = name
        self.createdAt = Date()
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

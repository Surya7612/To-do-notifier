import Foundation
import SwiftData

struct RetrievalMatch: Identifiable {
    let context: SavedContext
    let score: Double
    /// Why this came back, in the user's terms. Resurfacing without an
    /// explanation is indistinguishable from the app guessing.
    let reason: String

    var id: PersistentIdentifier { context.persistentModelID }
}

/// Structured, explainable relevance scoring — no embeddings.
///
/// The plan defers semantic retrieval until the structured version proves
/// insufficient, and this has a property embeddings lack: every match can say
/// exactly why it surfaced.
enum ContextRetriever {
    /// Below this, a match is noise. Resurfacing should be high-relevance and
    /// low-interruption rather than eager.
    private static let threshold = 2.0

    static func related(to observation: ScreenObservation,
                        among candidates: [SavedContext],
                        limit: Int = 3,
                        now: Date = Date()) -> [RetrievalMatch] {
        let screenTokens = tokenize(observation.recognizedText)
        let titleTokens = tokenize([observation.windowTitle, observation.appName]
            .compactMap { $0 }
            .joined(separator: " "))
        let visible = screenTokens.union(titleTokens)

        var matches: [RetrievalMatch] = []

        for candidate in candidates {
            var score = 0.0
            var reasons: [String] = []

            // A topic the user chose, literally present on screen now.
            let hitTopics = candidate.topics.filter { visible.contains($0) }
            if !hitTopics.isEmpty {
                score += 3.0 * Double(hitTopics.count)
                reasons.append(hitTopics.map { "#\($0)" }.joined(separator: " "))
            }

            if !candidate.windowTitle.isEmpty, candidate.windowTitle == observation.windowTitle {
                score += 2.5
                reasons.append("same window")
            } else if !candidate.sourceApp.isEmpty, candidate.sourceApp == observation.appName {
                score += 2.0
                reasons.append("same app")
            }

            let overlap = tokenize(candidate.intent).intersection(visible)
            if !overlap.isEmpty {
                score += min(3.0, 0.8 * Double(overlap.count))
                reasons.append("mentions \(overlap.sorted().prefix(2).joined(separator: ", "))")
            }

            guard score >= threshold else { continue }

            // Gentle recency nudge, never enough to promote an irrelevant item.
            let days = max(0, now.timeIntervalSince(candidate.createdAt) / 86_400)
            score += max(0, 1.0 - days / 30.0)

            matches.append(RetrievalMatch(context: candidate,
                                          score: score,
                                          reason: reasons.joined(separator: " · ")))
        }

        return matches.sorted { $0.score > $1.score }.prefix(limit).map { $0 }
    }

    /// Formats matches for the model, labelled so it cannot mistake the user's
    /// saved reasons for its own inference.
    static func promptLines(for matches: [RetrievalMatch]) -> [String] {
        matches.map { match in
            let when = match.context.createdAt.formatted(.relative(presentation: .named))
            let source = match.context.sourceApp.isEmpty ? "unknown app" : match.context.sourceApp
            return "- \"\(match.context.intent)\" (saved \(when) from \(source))"
        }
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "this", "that", "was", "were", "are", "his", "her",
        "you", "your", "our", "not", "from", "into", "over", "under", "out", "off",
        "how", "what", "when", "why", "who", "can", "will", "just", "about", "then",
        "there", "here", "have", "has", "had", "did", "does", "doing", "been", "being",
        "them", "they", "she", "him", "its", "it's", "all", "any", "some", "more", "most",
        "swift", "file", "app", "window", "code",
    ]

    private static func tokenize(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 2 && !stopwords.contains($0) }
        )
    }
}

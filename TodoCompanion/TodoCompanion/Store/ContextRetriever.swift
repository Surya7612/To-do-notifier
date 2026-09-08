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

/// Structured, explainable relevance scoring.
///
/// Meaning-based similarity is one signal among several rather than a
/// replacement for them, and it carries its own reason string like everything
/// else. That is the condition on using embeddings here at all: a match that
/// cannot say why it surfaced is indistinguishable from the app guessing, so a
/// vector distance is only allowed to *contribute* to a score it can also
/// explain. It is also additive, so with the feature off nothing changes.
enum ContextRetriever {
    /// Below this, a match is noise. Resurfacing should be high-relevance and
    /// low-interruption rather than eager.
    private static let threshold = 2.0

    /// Similarity below which two texts are treated as unrelated.
    ///
    /// Not near zero, because embedding models have a high similarity floor:
    /// measured with `nomic-embed-text`, plainly unrelated pairs score 0.31 to
    /// 0.40 while related ones score 0.62 to 0.69. This sits in that gap.
    static let similarityFloor = 0.55

    /// The most a meaning match can contribute. Below "same window" (2.5) on
    /// purpose: a shared window title is a fact, while this is a resemblance.
    static let similarityWeight = 2.2

    static func related(to observation: ScreenObservation,
                        among candidates: [SavedContext],
                        inProject activeProject: Project? = nil,
                        screenEmbedding: Embedding? = nil,
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

            // Worth more than any single screen signal, because the user said
            // this is what they are working on. It is a stated fact rather than
            // something read off the pixels.
            if let activeProject, candidate.project?.identifier == activeProject.identifier {
                score += 3.5
                reasons.append("in \(activeProject.name)")
            }

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

            // 1.2 rather than 1.0 so that two distinctive shared words clear the
            // threshold on their own. At 0.8 it took three, which made the best
            // signal available — the user's own reason echoing what is on screen
            // — weaker than the weakest one, being in the same application.
            let overlap = tokenize(candidate.intent).intersection(visible)
            if !overlap.isEmpty {
                score += min(3.0, 1.2 * Double(overlap.count))
                reasons.append("mentions \(overlap.sorted().prefix(2).joined(separator: ", "))")
            }

            // Catches what the literal signals cannot: a reason worded nothing
            // like the screen it belongs to. Only ever adds, so a save that
            // already matched on words is not penalised for also matching here,
            // and the reason names it as a resemblance rather than a fact.
            if let screenEmbedding,
               let candidateEmbedding = candidate.embedding,
               let contribution = meaningScore(candidateEmbedding, screenEmbedding) {
                score += contribution
                reasons.append("close in meaning")
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

    /// How much a similarity is worth, or nil if the two are unrelated.
    ///
    /// Scaled from the floor rather than from zero, so a similarity barely over
    /// the line is worth almost nothing and only a strong resemblance
    /// approaches the full weight. Without that, everything above the floor
    /// would arrive with the same near-maximum boost.
    static func meaningScore(_ candidate: Embedding, _ query: Embedding) -> Double? {
        guard let similarity = candidate.similarity(to: query),
              similarity >= similarityFloor
        else { return nil }

        let headroom = 1.0 - similarityFloor
        return similarityWeight * min(1.0, (similarity - similarityFloor) / headroom)
    }

    /// Ranks saves by meaning alone, for the library's search field.
    ///
    /// Separate from `related` because the inputs differ: there is a typed
    /// query rather than a screen, and no window, app, or project to score
    /// against. Returns nothing rather than everything when the query embeds to
    /// something no save resembles.
    static func matching(_ queryEmbedding: Embedding,
                         among candidates: [SavedContext],
                         limit: Int = 20) -> [RetrievalMatch] {
        candidates
            .compactMap { candidate -> RetrievalMatch? in
                guard let embedding = candidate.embedding,
                      let similarity = embedding.similarity(to: queryEmbedding),
                      similarity >= similarityFloor
                else { return nil }

                return RetrievalMatch(context: candidate,
                                      score: similarity,
                                      reason: "close in meaning")
            }
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { $0 }
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

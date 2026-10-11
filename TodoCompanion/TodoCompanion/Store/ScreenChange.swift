import Foundation

/// What changed on a screen since the last time the user kept it.
///
/// Pure OCR-token comparison — no model call. Shown at save time so a second
/// keep of the same window is about progress, not a duplicate.
nonisolated enum ScreenChange {
    struct Summary: Equatable {
        /// Short human line for the save status / AI summary preface.
        let line: String
        let addedCount: Int
        let removedCount: Int
    }

    /// Compares two OCR dumps. Empty strings yield nil (nothing to say).
    static func summary(previous: String, current: String) -> Summary? {
        let before = tokens(previous)
        let after = tokens(current)
        guard !before.isEmpty || !after.isEmpty else { return nil }

        let added = after.subtracting(before)
        let removed = before.subtracting(after)
        guard !added.isEmpty || !removed.isEmpty else {
            return Summary(line: "Screen text looks unchanged since the last keep",
                           addedCount: 0,
                           removedCount: 0)
        }

        var parts: [String] = []
        if !added.isEmpty {
            let sample = added.sorted().prefix(3).joined(separator: ", ")
            parts.append("new: \(sample)")
        }
        if !removed.isEmpty {
            let sample = removed.sorted().prefix(3).joined(separator: ", ")
            parts.append("gone: \(sample)")
        }
        return Summary(line: "Since last keep — \(parts.joined(separator: "; "))",
                       addedCount: added.count,
                       removedCount: removed.count)
    }

    /// Prior keep of the same window (prefer) or same app, newest first.
    static func priorKeep(for observation: ScreenObservation,
                          among candidates: [SavedContext]) -> SavedContext? {
        let title = observation.windowTitle ?? ""
        let app = observation.appName ?? ""

        let sameWindow = candidates.filter {
            !$0.windowTitle.isEmpty && $0.windowTitle == title
        }
        if let hit = sameWindow.max(by: { $0.createdAt < $1.createdAt }) {
            return hit
        }

        guard !app.isEmpty else { return nil }
        return candidates
            .filter { $0.sourceApp == app && $0.windowTitle.isEmpty == title.isEmpty }
            .max(by: { $0.createdAt < $1.createdAt })
    }

    private static let stopwords: Set<String> = [
        "the", "and", "for", "with", "this", "that", "was", "are", "you", "your",
        "from", "into", "have", "has", "not", "but", "all", "any", "can", "will",
    ]

    private static func tokens(_ text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 2 && !stopwords.contains($0) }
        )
    }
}

import Foundation

/// Whether bringing things back is earning its place.
///
/// The plan's success test is "I would have forgotten that if it had not
/// brought it back", and no relevance score can answer it — only the user
/// reaching for what was shown can. These are counted on this Mac and never
/// leave it. Pure so the wording is testable.
nonisolated enum ResurfaceStats {
    struct Counts: Equatable {
        var keepsShown = 0
        var timesShown = 0
        var timesUsed = 0
    }

    static func counts(_ pairs: [(shown: Int, used: Int)]) -> Counts {
        pairs.reduce(into: Counts()) { total, pair in
            guard pair.shown > 0 else { return }
            total.keepsShown += 1
            total.timesShown += pair.shown
            total.timesUsed += min(pair.used, pair.shown)
        }
    }

    /// One line for the library, or nil before anything has been shown.
    static func summary(_ counts: Counts) -> String? {
        guard counts.timesShown > 0 else { return nil }
        let keeps = counts.keepsShown == 1 ? "1 keep" : "\(counts.keepsShown) keeps"
        let times = counts.timesShown == 1 ? "once" : "\(counts.timesShown) times"
        let used = switch counts.timesUsed {
        case 0: "you have not opened any of them yet"
        case 1: "you reached for one once"
        default: "you reached for them \(counts.timesUsed) times"
        }
        return "Max brought back \(keeps) \(times); \(used)."
    }

    /// The per-keep line on its detail page.
    static func detail(shown: Int, used: Int) -> String? {
        guard shown > 0 else { return nil }
        let times = shown == 1 ? "once" : "\(shown) times"
        let usedText = switch min(used, shown) {
        case 0: "not opened from there yet"
        case 1: "opened once"
        default: "opened \(min(used, shown)) times"
        }
        return "Brought back \(times) · \(usedText)"
    }
}

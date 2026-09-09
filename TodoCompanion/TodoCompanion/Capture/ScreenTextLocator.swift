import CoreGraphics
import Foundation

/// Finds the control an answer named, in the text Vision read off the screen.
///
/// Built on OCR rather than the accessibility tree, and not as a concession.
/// Max is shown a screenshot, so it can only name what is legibly on it — which
/// means the words it uses are words OCR already has. An accessibility tree
/// knows about controls Max could never have referred to, and is thin or absent
/// in exactly the applications this is most useful for: Qt, Electron, games,
/// anything that draws its own interface. Reading pixels works wherever the user
/// can see.
///
/// The consequence is that an unlabelled glyph cannot be found, which is the
/// right failure: Max describes those positionally rather than by name, and a
/// confident box over the wrong icon is worse than no box.
nonisolated enum ScreenTextLocator {
    struct Match: Equatable, Sendable {
        /// Normalized, origin bottom-left, as Vision reports boxes.
        let boundingBox: CGRect
        /// The words matched. Shown on the button, so the user can tell what
        /// will be pointed at before anything is drawn over their screen.
        let text: String
    }

    /// Labels longer than this are almost certainly a sentence Max wrote rather
    /// than something printed on a control.
    static let maximumWords = 4

    /// Below this a "match" is noise: two characters appear inside half the
    /// words in any answer.
    static let minimumLength = 3

    /// An unquoted match must clear this to be believed, because the prompt asks
    /// Max to quote a label it means. "Fairlight" is a name; "menu" is a noun
    /// Max uses to describe things, and matching it would point at the word
    /// "Menu" printed somewhere unrelated.
    static let minimumUnquotedLength = 6

    /// - Parameter requiringQuoted: Drops the inferred-from-prose path
    ///   entirely, so only a label Max put in double quotes can match.
    ///
    ///   Used by the follow-along highlight, which draws while the answer is
    ///   being read aloud and so cannot show the user its match beforehand the
    ///   way the button does. A quoted label is not a guess — `Prompt.system`
    ///   asks for a control's label character for character, so quoting is Max
    ///   stating which words it meant. Requiring it is what keeps the standing
    ///   rule intact: nothing unexplained is ever drawn on the screen.
    static func locate(named answer: String,
                       in regions: [TextRegion],
                       requiringQuoted: Bool = false) -> Match? {
        guard !regions.isEmpty else { return nil }

        let haystack = answer.lowercased()
        let quoted = quotedPhrases(in: answer)
        guard !requiringQuoted || !quoted.isEmpty else { return nil }

        var best: (score: Int, match: Match)?

        for (_, unordered) in Dictionary(grouping: regions, by: \.line) {
            let words = unordered.sorted { $0.position < $1.position }

            for start in words.indices {
                for length in 1...maximumWords where start + length <= words.count {
                    let run = Array(words[start..<(start + length)])
                    let phrase = run.map(\.string).joined(separator: " ")

                    guard let score = score(phrase: phrase,
                                            in: haystack,
                                            quoted: quoted,
                                            requiringQuoted: requiringQuoted),
                          score > (best?.score ?? 0)
                    else { continue }

                    best = (score, Match(boundingBox: union(of: run), text: phrase))
                }
            }
        }

        return best?.match
    }

    /// Vision's normalized box placed into global screen coordinates.
    ///
    /// `frame` is the area of the screen the capture covers: the whole display
    /// normally, or the dragged-out region once the user has narrowed it.
    static func screenRect(for boundingBox: CGRect, in frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + boundingBox.minX * frame.width,
               y: frame.minY + boundingBox.minY * frame.height,
               width: boundingBox.width * frame.width,
               height: boundingBox.height * frame.height)
    }

    /// Higher is a better candidate; nil means ineligible.
    ///
    /// Length carries the score because a longer label is a more specific claim:
    /// "Color Page" beats "Color", which beats "Page". Quoting outranks all of
    /// it, since that is Max stating which words it meant rather than us
    /// inferring them from prose.
    private static func score(phrase: String,
                              in haystack: String,
                              quoted: Set<String>,
                              requiringQuoted: Bool = false) -> Int? {
        let cleaned = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= minimumLength, cleaned.contains(where: \.isLetter) else { return nil }

        let needle = cleaned.lowercased()
        guard haystack.containsWholeWord(needle) else { return nil }

        if quoted.contains(needle) { return cleaned.count + 100 }
        guard !requiringQuoted else { return nil }

        // Unquoted, this is a guess drawn from ordinary prose, so it has to earn
        // it: long enough not to be a common word, never a word Max uses to talk
        // *about* controls, and printed on screen the way a label is printed.
        guard !descriptiveWords.contains(needle),
              cleaned.count >= minimumUnquotedLength || cleaned.contains(" "),
              isPrintedLikeALabel(cleaned)
        else { return nil }

        return cleaned.count
    }

    /// Whether the words, *as Vision read them off the screen*, are printed the
    /// way a control's label is printed rather than the way prose is.
    ///
    /// Length alone was standing in for this and is a poor proxy: "should",
    /// "before" and "because" all clear six characters, so an answer that merely
    /// used one of them in a sentence would offer to draw a box around it
    /// wherever it happened to appear. The observed case was Max asking "When
    /// should I remind you?" and offering to point at "should".
    ///
    /// A capital, an interior capital or a digit is what separates `Fairlight`,
    /// `Deliver` and `qwen3` from ordinary running text. This deliberately gives
    /// up on an entirely lowercase label, which is the cheaper mistake: that
    /// yields no box, where the alternative draws a confident one over a word
    /// nobody was talking about.
    private static func isPrintedLikeALabel(_ phrase: String) -> Bool {
        phrase.split(separator: " ").contains { word in
            guard let first = word.first else { return false }
            return first.isUppercase
                || word.contains(where: \.isNumber)
                || word.dropFirst().contains(where: \.isUppercase)
        }
    }

    /// Text inside double quotes, straight or curly, lowercased.
    private static func quotedPhrases(in answer: String) -> Set<String> {
        var phrases: Set<String> = []
        var current: String?

        for character in answer {
            switch character {
            case "\"", "\u{201C}", "\u{201D}", "`":
                if let open = current {
                    let trimmed = open.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.isEmpty { phrases.insert(trimmed.lowercased()) }
                    current = nil
                } else {
                    current = ""
                }
            default:
                current?.append(character)
            }
        }

        return phrases
    }

    /// Words Max uses to describe a control rather than to name one. Matching
    /// these points at whatever unrelated place the word happens to be printed.
    ///
    /// The second group is ordinary prose rather than interface vocabulary. It
    /// is here because `isPrintedLikeALabel` accepts a leading capital, and one
    /// of these beginning a sentence on screen would otherwise qualify.
    private static let descriptiveWords: Set<String> = [
        "button", "buttons", "menu", "menus", "panel", "panels", "window",
        "windows", "screen", "toolbar", "sidebar", "tab", "tabs", "option",
        "options", "setting", "settings", "field", "fields", "dialog", "icon",
        "click", "select", "choose", "press", "open", "the", "this", "that",
        "there", "here", "then", "your", "you",

        "should", "would", "could", "before", "after", "because", "instead",
        "already", "another", "without", "through", "something", "anything",
        "everything", "nothing", "about", "these", "those", "which", "where",
        "when", "while", "again", "still", "right", "first", "next", "same",
    ]

    private static func union(of regions: [TextRegion]) -> CGRect {
        regions.dropFirst().reduce(regions[0].boundingBox) { $0.union($1.boundingBox) }
    }
}

private extension String {
    /// Containment that will not match inside a longer word, so an answer about
    /// "colours" does not point at a "Color" tab.
    nonisolated func containsWholeWord(_ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }
        var searchFrom = startIndex

        while let found = range(of: needle, range: searchFrom..<endIndex) {
            let openingIsClean = found.lowerBound == startIndex
                || !self[self.index(before: found.lowerBound)].continuesAWord
            let closingIsClean = found.upperBound == endIndex
                || !self[found.upperBound].continuesAWord

            if openingIsClean && closingIsClean { return true }
            guard found.lowerBound < endIndex else { return false }
            searchFrom = index(after: found.lowerBound)
        }

        return false
    }
}

private extension Character {
    nonisolated var continuesAWord: Bool { isLetter || isNumber }
}

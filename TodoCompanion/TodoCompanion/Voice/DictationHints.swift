import Foundation

/// Words to tell the recognizer to expect, taken from what is on screen.
///
/// This app knows something a general dictation engine cannot: the user is
/// about to speak a question *about the screen in front of them*, and the words
/// on it have already been read by OCR. So the proper nouns most likely to be
/// said — an application's name, a panel, a symbol in their own code — are
/// sitting in the capture, and those are exactly the words a general English
/// model mishears. "Fairlight" becomes "fair light", "SwiftData" becomes "Swift
/// data", "Ollama" becomes anything at all.
///
/// Only distinctive words are offered. `contextualStrings` is a small budget
/// that biases the model, so filling it with ordinary English spends it on
/// words the recognizer was never going to get wrong, and biasing towards a
/// common word can make things worse rather than better.
nonisolated enum DictationHints {
    /// Apple documents `contextualStrings` as a short list, and a long one
    /// dilutes each entry's weight as well as costing time to apply.
    static let limit = 80

    /// A word has to be at least this long to be worth a slot. Short tokens on
    /// a screen are mostly labels, units and fragments of code punctuation.
    static let minimumLength = 4

    /// Long enough to be an identifier rather than a word, and past the point
    /// where anyone would say it aloud.
    static let maximumLength = 24

    /// Words that clear the length bar but are not worth biasing towards.
    ///
    /// Ordinary English that happens to be capitalised at the start of a line,
    /// which OCR produces a great deal of.
    private static let ordinary: Set<String> = [
        "this", "that", "there", "these", "those", "then", "than", "with",
        "from", "have", "here", "what", "when", "where", "which", "while",
        "your", "you", "the", "and", "for", "not", "but", "all", "any",
        "can", "will", "would", "should", "could", "about", "after", "again",
        "also", "back", "been", "before", "being", "both", "each", "into",
        "just", "like", "make", "more", "most", "only", "open", "other",
        "over", "same", "some", "such", "take", "them", "they", "time",
        "very", "want", "well", "were", "will", "work", "click", "close",
        "file", "edit", "view", "help", "window", "menu", "save", "cancel",
        "done", "next", "previous", "settings", "search", "delete", "new",
    ]

    /// Picks the words worth expecting, most distinctive first.
    ///
    /// Ordered rather than merely filtered, because the list is truncated: if
    /// it has to be cut, the interior-capital identifiers are the ones worth
    /// keeping and an ordinary capitalised noun is the one to drop.
    static func from(screenText: String, projectNames: [String] = []) -> [String] {
        var distinctive: [String] = []
        var capitalised: [String] = []
        var seen = Set<String>()

        // Stated by the user, so they outrank anything read off the screen and
        // are never truncated away.
        for name in projectNames {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed.lowercased()).inserted else { continue }
            distinctive.append(trimmed)
        }

        for token in tokens(in: screenText) {
            guard token.count >= minimumLength, token.count <= maximumLength else { continue }
            guard !ordinary.contains(token.lowercased()) else { continue }
            guard seen.insert(token.lowercased()).inserted else { continue }

            if hasInteriorCapital(token) || mixesLettersAndDigits(token) {
                distinctive.append(token)
            } else if token.first?.isUppercase == true {
                capitalised.append(token)
            }
        }

        return Array((distinctive + capitalised).prefix(limit))
    }

    /// Splits on anything that is not part of a word, keeping the interior
    /// punctuation that identifiers use.
    private static func tokens(in text: String) -> [String] {
        text.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
    }

    /// `SwiftData`, `DaVinci`, `xcodebuild` — a shape no English word has, and
    /// the shape a recognizer splits into two words.
    private static func hasInteriorCapital(_ token: String) -> Bool {
        token.dropFirst().contains { $0.isUppercase }
    }

    private static func mixesLettersAndDigits(_ token: String) -> Bool {
        token.contains(where: \.isNumber) && token.contains(where: \.isLetter)
    }
}

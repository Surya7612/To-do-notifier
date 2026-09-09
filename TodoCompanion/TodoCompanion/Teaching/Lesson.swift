import Foundation

/// An answer read as a sequence of things to be shown, one at a time.
///
/// There is no new syntax here, and that is the whole design. A lesson is an
/// ordinary numbered list — which `AnswerContent` already parses and the panel
/// already draws — whose items quote the on-screen text they are about, which
/// `Prompt.system` already asks Max to do and `ScreenTextLocator` already knows
/// how to resolve. Teaching mode adds a paragraph of prompt guidance and a
/// player; it invents no format for a model to get wrong.
///
/// That matters more than it looks. A bespoke block — JSON, or a line format
/// with coordinates in it — would be a second thing the model has to produce
/// correctly, and the failure would be a lesson that silently does not appear.
/// Reusing the list means a reply that ignores every instruction is still a
/// perfectly good answer, drawn the way answers always are.
///
/// Pure, so the whole of it is testable without a screen or a model.
nonisolated struct Lesson: Equatable {
    struct Step: Equatable {
        /// As printed in the list, and as spoken.
        let text: String
        /// The labels this step is about, in the order Max quoted them. These
        /// are names, never positions: where they are on screen is decided by
        /// Vision's OCR boxes, never by the model.
        let anchors: [String]
        /// Whether to join the boxes with arrows rather than leave them
        /// separate. True when Max wrote an arrow between the quoted labels.
        let isConnected: Bool

        /// The few words drawn beside the mark, for the reader who is looking
        /// at their code rather than at the panel.
        ///
        /// The step's own opening, cut at a word: the sentence is already in
        /// the panel in full, and the caption exists to say which step this box
        /// belongs to, not to reproduce the lesson on top of the user's work.
        var caption: String {
            let stripped = text.replacingOccurrences(of: "\u{201C}", with: "\"")
                .replacingOccurrences(of: "\u{201D}", with: "\"")
            guard stripped.count > Lesson.captionLength else { return stripped }

            let cut = stripped.prefix(Lesson.captionLength)
            guard let lastGap = cut.lastIndex(of: " ") else { return String(cut) + "…" }
            return cut[..<lastGap] + "…"
        }
    }

    /// Long enough to carry a clause, short enough not to become a second
    /// panel floating over the user's editor.
    static let captionLength = 64

    /// Max writing one label into another. The only mark this app draws that
    /// is not a box, and it is drawn because Max *stated* a relation between
    /// two things it named — not because two names happened to be in one step,
    /// which would be this app inferring a connection from adjacency.
    static let connector: Character = "\u{2192}"

    let steps: [Step]

    /// One or two items is a list, not a lesson. Playing a two-step lesson
    /// costs the user a mode to get out of and shows them one box they would
    /// have got from ⌘P anyway.
    static let minimumSteps = 3

    /// Reads a lesson out of an answer, or decides there isn't one.
    ///
    /// Deliberately willing to fail. A small local model will sometimes write
    /// prose when it was asked for steps, and the right outcome then is the
    /// ordinary answer it produced rather than an empty lesson bar over it.
    static func from(answer: String) -> Lesson? {
        let items = AnswerContent.blocks(in: answer).compactMap { block -> [String]? in
            guard case let .numbered(items) = block else { return nil }
            return items
        }.first

        guard let items, items.count >= minimumSteps else { return nil }

        let steps = items.map { item in
            Step(text: item,
                 anchors: ScreenTextLocator.quotedLabels(in: item),
                 isConnected: item.contains(connector))
        }

        // Every step naming nothing is a numbered list that happens to be in
        // the answer — "1. sort 2. recurse 3. backtrack" — rather than a walk
        // through what is on screen. Playing it would put a mode on the panel
        // and never draw anything.
        guard steps.contains(where: { !$0.anchors.isEmpty }) else { return nil }

        return Lesson(steps: steps)
    }

    /// The step a spoken clause belongs to, searching forward from the one
    /// showing.
    ///
    /// Matched on the quoted labels rather than on the words of the sentence,
    /// for the same reason the follow-along box is: a quote is Max stating what
    /// it meant, where a similarity between two sentences is this app guessing.
    /// It also survives the voice's markup stripping, which rewrites the
    /// sentence but leaves the quotes alone.
    ///
    /// Never moves backwards. Speech arrives in order, and a label mentioned
    /// again in a later step would otherwise drag the lesson back to the first
    /// step that used it.
    func step(spokenIn clause: String, notBefore current: Int) -> Int? {
        let quoted = Set(ScreenTextLocator.quotedLabels(in: clause).map { $0.lowercased() })
        guard !quoted.isEmpty else { return nil }

        return steps.indices
            .filter { $0 >= current }
            .first { index in
                steps[index].anchors.contains { quoted.contains($0.lowercased()) }
            }
    }
}

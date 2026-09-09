import AppKit
import SwiftUI

/// An answer, split into the pieces the panel draws differently.
///
/// Max writes Markdown whether or not anyone asks it to — it reaches for lists
/// and emphasis on its own, and `Prompt.formatting` now asks outright for fenced
/// code. The panel used to render the whole reply as one run of proportional
/// body text, which put backticks and asterisks on screen as literal characters
/// and set code in a font where alignment and the difference between `l` and `1`
/// are exactly what the reader needs.
///
/// Pure, so the parsing is testable without a view. Streaming is why the shape
/// is what it is: this runs again on every chunk that arrives, against text
/// whose last fence has usually not been closed yet.
nonisolated enum AnswerContent {
    enum Block: Equatable {
        case heading(String)
        case paragraph(String)
        case bulleted([String])
        case numbered([String])
        case code(Code)
    }

    struct Code: Equatable {
        /// As written after the opening fence, or nil when it was bare.
        let language: String?
        let text: String
        /// False until the closing fence arrives. The panel says so rather than
        /// showing a block that looks finished and then keeps growing.
        let isStreaming: Bool
    }

    private static let fence = "```"

    static func blocks(in answer: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        var bulleted: [String] = []
        var numbered: [String] = []

        func flush() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: " ")))
                paragraph = []
            }
            if !bulleted.isEmpty {
                blocks.append(.bulleted(bulleted))
                bulleted = []
            }
            if !numbered.isEmpty {
                blocks.append(.numbered(numbered))
                numbered = []
            }
        }

        var lines = answer.components(separatedBy: .newlines)[...]

        while let line = lines.first {
            lines = lines.dropFirst()
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix(fence) {
                flush()
                blocks.append(.code(consumeFence(opener: trimmed, from: &lines)))
                continue
            }

            if trimmed.isEmpty {
                flush()
                continue
            }

            if let heading = headingText(in: trimmed) {
                flush()
                blocks.append(.heading(heading))
                continue
            }

            if let item = listItem(in: trimmed, markers: bulletMarkers) {
                if !paragraph.isEmpty || !numbered.isEmpty { flush() }
                bulleted.append(item)
                continue
            }

            if let item = numberedItem(in: trimmed) {
                if !paragraph.isEmpty || !bulleted.isEmpty { flush() }
                numbered.append(item)
                continue
            }

            if !bulleted.isEmpty || !numbered.isEmpty { flush() }
            paragraph.append(trimmed)
        }

        flush()
        return blocks
    }

    /// Everything up to the closing fence, or to the end of what has arrived.
    private static func consumeFence(opener: String,
                                     from lines: inout ArraySlice<String>) -> Code {
        var body: [String] = []
        var isClosed = false

        while let line = lines.first {
            lines = lines.dropFirst()
            if line.trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                isClosed = true
                break
            }
            body.append(line)
        }

        let language = String(opener.dropFirst(fence.count))
            .trimmingCharacters(in: .whitespaces)
            .lowercased()

        return Code(language: language.isEmpty ? nil : language,
                    text: body.joined(separator: "\n"),
                    isStreaming: !isClosed)
    }

    private static let bulletMarkers = ["- ", "* ", "+ ", "• "]

    private static func headingText(in line: String) -> String? {
        guard line.hasPrefix("#") else { return nil }
        let text = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }

    private static func listItem(in line: String, markers: [String]) -> String? {
        for marker in markers where line.hasPrefix(marker) {
            let text = String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
            return text.isEmpty ? nil : text
        }
        return nil
    }

    /// `1. ` or `1) `, which is how a model writes an ordered list.
    ///
    /// Both bounds below are there to keep ordinary prose out. The whitespace is
    /// required because "3.5 GB free" opens with digits and a period and is a
    /// measurement; the digit cap because "2024. That was the year" would
    /// otherwise be step two thousand and twenty-four, and an answer capped at
    /// four sentences has no hundredth step.
    private static let maximumListNumberDigits = 2

    private static func numberedItem(in line: String) -> String? {
        let digits = line.prefix(while: \.isNumber)
        guard !digits.isEmpty, digits.count <= maximumListNumberDigits else { return nil }

        var rest = line.dropFirst(digits.count)
        guard let separator = rest.first, separator == "." || separator == ")" else { return nil }

        rest = rest.dropFirst()
        guard rest.first?.isWhitespace == true else { return nil }

        let text = rest.trimmingCharacters(in: .whitespaces)
        return text.isEmpty ? nil : text
    }
}

extension AnswerContent {
    /// Inline Markdown, with the labels Max quoted picked out.
    ///
    /// The quoting is not decoration. `Prompt.system` asks for a control's exact
    /// on-screen label in double quotes, and `ScreenTextLocator` trusts a quoted
    /// phrase over anything it infers from prose — so these are precisely the
    /// words the app is willing to draw a box around. They are drawn **bold
    /// label colour** (near-black in Light Mode) so they read as emphasis in the
    /// answer rather than as another amber mark competing with the box on
    /// screen — that box keeps `DS.Pointer.mark`.
    ///
    /// Colour and weight are applied on the `AttributedString` itself. Putting
    /// `.foregroundStyle` / `.font` on the `Text` that draws this wiped the
    /// per-run attributes, so quotes either vanished into the body or kept
    /// looking like the old amber depending on the OS.
    static func styled(_ text: String) -> AttributedString {
        var attributed = (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)

        attributed.font = .callout
        // Quieter than the user's question above, without a view-level
        // foregroundStyle that would also recolour the quotes.
        attributed.foregroundColor = Color.primary.opacity(0.82)

        // Collected before mutating, since changing an attribute invalidates
        // the run boundaries being iterated.
        let codeRanges = attributed.runs
            .filter { $0.inlinePresentationIntent?.contains(.code) == true }
            .map(\.range)

        for range in codeRanges {
            attributed[range].font = .system(.callout, design: .monospaced)
        }

        for range in quotedRanges(in: attributed) {
            // `labelColor` tracks Light/Dark; plain `.black` would vanish at night.
            attributed[range].foregroundColor = Color(nsColor: .labelColor)
            attributed[range].font = .callout.weight(.bold)
        }

        return attributed
    }

    /// Ranges covering each `"quoted phrase"`, quotes included.
    private static func quotedRanges(in attributed: AttributedString) -> [Range<AttributedString.Index>] {
        var ranges: [Range<AttributedString.Index>] = []
        var opening: AttributedString.Index?
        var index = attributed.startIndex

        while index < attributed.endIndex {
            let next = attributed.index(afterCharacter: index)

            if isQuote(attributed.characters[index]) {
                if let start = opening {
                    ranges.append(start..<next)
                    opening = nil
                } else {
                    opening = index
                }
            }

            index = next
        }

        // An unclosed quote is left alone: mid-stream it is a label Max is still
        // in the middle of writing, and colouring the rest of the answer as one
        // would be a change the reader watches happen and then undo.
        return ranges
    }

    private static func isQuote(_ character: Character) -> Bool {
        character == "\"" || character == "\u{201C}" || character == "\u{201D}"
    }
}

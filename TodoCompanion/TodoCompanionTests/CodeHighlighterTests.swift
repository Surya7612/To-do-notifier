import Foundation
import SwiftUI
import Testing

@testable import TodoCompanion

/// Colouring is cosmetic and getting it wrong costs nothing, with one
/// exception: the highlighter rebuilds the text character by character, so a
/// mistake in the scanner can silently *drop* part of the code. That is the
/// property these pin. Which token got which colour is deliberately barely
/// asserted, so the palette and the keyword lists stay free to change.
@Suite("Colouring a code block")
struct CodeHighlighterTests {
    /// The one thing that must never happen. The panel shows this instead of
    /// the model's reply, and the user copies it into their editor.
    @Test("every character survives, in order")
    func textIsNeverAltered() {
        let samples = [
            "let x = 1",
            "func f() {\n    // note\n    return \"a\\\"b\"\n}",
            "/* unterminated block comment\nstill going",
            "print('unterminated string",
            "  \t indented\n\n\nblank lines kept",
            "",
        ]

        for sample in samples {
            let highlighted = CodeHighlighter.highlight(sample, language: "swift")
            #expect(String(highlighted.characters) == sample)
        }
    }

    @Test("text survives whatever language it is labelled with")
    func textSurvivesEveryLanguage() {
        let sample = "a = b # c \"d\" /* e */"

        for language in ["swift", "python", "javascript", "bash", "json", "cobol", nil] {
            #expect(String(CodeHighlighter.highlight(sample, language: language).characters) == sample)
        }
    }

    @Test("a comment is coloured as one")
    func commentsAreColoured() {
        let highlighted = CodeHighlighter.highlight("let x = 1 // why", language: "swift")
        let comments = highlighted.runs.filter { $0.foregroundColor == DS.Code.comment }

        #expect(comments.contains { String(highlighted[$0.range].characters).contains("// why") })
    }

    /// A block comment is the only token that outlives its line, so it is the
    /// only one whose state has to be threaded between them.
    @Test("a block comment keeps its colour across lines")
    func blockCommentsSpanLines() {
        let highlighted = CodeHighlighter.highlight("/* one\ntwo */ let x = 1", language: "swift")

        let commented = highlighted.runs
            .filter { $0.foregroundColor == DS.Code.comment }
            .map { String(highlighted[$0.range].characters) }
            .joined()

        #expect(commented.contains("two */"))
        // And it stops at the closing marker rather than swallowing the rest.
        #expect(!commented.contains("let x"))
    }

    /// `#` opens a comment in Python and does not in Swift, which is the whole
    /// reason the language tag is asked for in the prompt.
    @Test("comment markers follow the language")
    func commentMarkersAreLanguageSpecific() {
        let python = CodeHighlighter.highlight("x = 1 # note", language: "python")
        #expect(python.runs.contains {
            $0.foregroundColor == DS.Code.comment
                && String(python[$0.range].characters).contains("# note")
        })

        let json = CodeHighlighter.highlight("{\"a\": 1} # not a comment", language: "json")
        #expect(!json.runs.contains {
            $0.foregroundColor == DS.Code.comment
                && String(json[$0.range].characters).contains("not a comment")
        })
    }
}

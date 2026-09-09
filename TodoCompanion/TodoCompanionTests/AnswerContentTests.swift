import Foundation
import SwiftUI
import Testing

@testable import TodoCompanion

/// What the panel draws is decided here. The failures are silent in the sense
/// that matters: a block parsed wrongly still renders, as the wrong thing — a
/// code fence shown as a paragraph of prose, or a list flattened into a
/// sentence — so nothing errors and the answer just reads worse.
@Suite("Splitting an answer into what the panel draws")
struct AnswerContentTests {
    @Test("plain prose is one paragraph, with the line breaks joined up")
    func prosePassesThrough() {
        let blocks = AnswerContent.blocks(in: "Open the panel.\nThen press return.")

        #expect(blocks == [.paragraph("Open the panel. Then press return.")])
    }

    @Test("a blank line starts a new paragraph")
    func blankLineSeparatesParagraphs() {
        let blocks = AnswerContent.blocks(in: "First thought.\n\nSecond thought.")

        #expect(blocks == [.paragraph("First thought."), .paragraph("Second thought.")])
    }

    @Test("a fenced block keeps its language and its own indentation")
    func fenceCarriesLanguageAndWhitespace() throws {
        let answer = """
        Try this:

        ```swift
        func main() {
            print("hi")
        }
        ```
        """

        let blocks = AnswerContent.blocks(in: answer)
        #expect(blocks.count == 2)

        guard case let .code(code) = blocks[1] else {
            Issue.record("expected a code block, got \(blocks[1])")
            return
        }

        #expect(code.language == "swift")
        #expect(code.isStreaming == false)
        // Leading whitespace is the thing a proportional font destroys, so it
        // must survive parsing intact.
        #expect(code.text.contains("    print(\"hi\")"))
    }

    /// This runs on every streamed chunk, so most of the time it is looking at
    /// a fence that has been opened and not yet closed. Treating that as
    /// unparseable would leave the code as raw backticks until the last token
    /// arrived, and then snap it into place.
    @Test("an unclosed fence is a code block that says it is still arriving")
    func unclosedFenceIsStillCode() throws {
        let blocks = AnswerContent.blocks(in: "Here:\n\n```bash\nbrew install oll")

        guard case let .code(code) = blocks[1] else {
            Issue.record("expected a code block, got \(blocks[1])")
            return
        }

        #expect(code.isStreaming)
        #expect(code.text == "brew install oll")
    }

    @Test("a bare fence has no language rather than an empty one")
    func bareFenceHasNoLanguage() throws {
        let blocks = AnswerContent.blocks(in: "```\nsome text\n```")

        guard case let .code(code) = blocks[0] else {
            Issue.record("expected a code block, got \(blocks[0])")
            return
        }

        #expect(code.language == nil)
    }

    @Test("bullets and numbered steps become lists, with the markers stripped")
    func listsAreRecognized() {
        let bulleted = AnswerContent.blocks(in: "- one\n- two")
        #expect(bulleted == [.bulleted(["one", "two"])])

        let numbered = AnswerContent.blocks(in: "1. first\n2) second")
        #expect(numbered == [.numbered(["first", "second"])])
    }

    /// A list arriving straight after a sentence with no blank line between
    /// them is the common shape of a model's answer, and running them together
    /// puts "Do this:" on the same line as the first step.
    @Test("a list breaks out of the paragraph above it without a blank line")
    func listInterruptsAParagraph() {
        let blocks = AnswerContent.blocks(in: "Do this:\n- one\n- two")

        #expect(blocks == [.paragraph("Do this:"), .bulleted(["one", "two"])])
    }

    /// Both of these open with digits and a period, which is exactly the shape
    /// of an ordered list item, and neither is one. The first was found by this
    /// test rather than by reading the code.
    @Test("a measurement or a year at the start of a line is not a numbered list")
    func digitsAloneDoNotMakeAList() {
        #expect(AnswerContent.blocks(in: "3.5 GB free on the disk")
            == [.paragraph("3.5 GB free on the disk")])

        #expect(AnswerContent.blocks(in: "2024. That was the year it shipped.")
            == [.paragraph("2024. That was the year it shipped.")])
    }

    @Test("a heading is its own block, without its hashes")
    func headingIsSeparate() {
        #expect(AnswerContent.blocks(in: "## What went wrong") == [.heading("What went wrong")])
    }

    @Test("nothing in, nothing out")
    func emptyAnswerHasNoBlocks() {
        #expect(AnswerContent.blocks(in: "").isEmpty)
        #expect(AnswerContent.blocks(in: "\n\n  \n").isEmpty)
    }
}

/// The quoted-label styling is the panel's half of the same claim the screen
/// highlight makes: these are the words the app believes are printed on screen.
@Suite("Styling an answer's inline text")
struct AnswerStylingTests {
    @Test("styling never changes the words, only how they are drawn")
    func stylingPreservesText() {
        let plain = "Click the \"Color\" page, then press Deliver."

        #expect(String(AnswerContent.styled(plain).characters) == plain)
    }

    @Test("a quoted label is coloured the same as the box drawn on screen")
    func quotedLabelIsEmphasized() {
        let styled = AnswerContent.styled("Click the \"Color\" page.")
        let coloured = styled.runs.filter { $0.foregroundColor == DS.Pointer.mark }

        #expect(coloured.count == 1)
        #expect(coloured.first.map { String(styled[$0.range].characters) } == "\"Color\"")
    }

    /// Mid-stream the answer regularly ends inside a quotation. Treating the
    /// open quote as a label would colour everything after it and then undo
    /// that a moment later, which the reader watches happen.
    @Test("an unclosed quote is left alone")
    func unclosedQuoteIsNotStyled() {
        let styled = AnswerContent.styled("Click the \"Col")

        #expect(!styled.runs.contains { $0.foregroundColor == DS.Pointer.mark })
    }

    @Test("markdown emphasis is applied rather than printed")
    func markdownIsInterpreted() {
        // The asterisks were previously visible on screen as characters.
        #expect(String(AnswerContent.styled("that is **important**").characters)
            == "that is important")
    }
}

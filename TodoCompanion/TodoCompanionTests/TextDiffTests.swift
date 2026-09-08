import Foundation
import Testing
@testable import TodoCompanion

/// The diff is what the user reads before agreeing to overwrite their own file,
/// so it is the safety mechanism rather than a presentation detail. A diff that
/// under-reports a change would get one applied that nobody agreed to.
@Suite("Text diff")
struct TextDiffTests {
    private func kinds(_ original: String, _ proposed: String) -> [TextDiff.Line.Kind] {
        TextDiff.compare(original, to: proposed).map(\.kind)
    }

    @Test("identical text has no changes")
    func identicalIsClean() {
        let text = "one\ntwo\nthree"
        let lines = TextDiff.compare(text, to: text)

        #expect(lines.allSatisfy { $0.kind == .unchanged })
        #expect(TextDiff.summary(of: lines).isEmpty)
        #expect(TextDiff.hunks(lines).isEmpty)
    }

    @Test("a changed line reads as one removal and one addition")
    func changedLine() {
        let lines = TextDiff.compare("one\ntwo\nthree", to: "one\nTWO\nthree")
        let summary = TextDiff.summary(of: lines)

        #expect(summary.added == 1)
        #expect(summary.removed == 1)
        #expect(summary.description == "+1 −1")
    }

    @Test("an inserted line is an addition only")
    func insertedLine() {
        #expect(kinds("one\ntwo", "one\nmiddle\ntwo") == [.unchanged, .added, .unchanged])
    }

    @Test("a deleted line is a removal only")
    func deletedLine() {
        #expect(kinds("one\ntwo\nthree", "one\nthree") == [.unchanged, .removed, .unchanged])
    }

    @Test("every line of a rewritten file is accounted for")
    func fullRewrite() {
        let lines = TextDiff.compare("a\nb", to: "x\ny\nz")
        let summary = TextDiff.summary(of: lines)

        #expect(summary.removed == 2)
        #expect(summary.added == 3)
    }

    @Test("line numbers refer to the file each side came from")
    func numbersFollowTheirOwnFile() throws {
        let lines = TextDiff.compare("keep\ndrop\nkeep2", to: "keep\nadd\nkeep2")

        let removed = try #require(lines.first { $0.kind == .removed })
        #expect(removed.oldNumber == 2)
        #expect(removed.newNumber == nil)

        let added = try #require(lines.first { $0.kind == .added })
        #expect(added.newNumber == 2)
        #expect(added.oldNumber == nil)
    }

    @Test("going from or to an empty file works")
    func emptySides() {
        #expect(TextDiff.summary(of: TextDiff.compare("", to: "new")).added == 1)
        #expect(TextDiff.summary(of: TextDiff.compare("old", to: "")).removed == 1)
    }

    /// The panel cannot show a whole file, so only the changed regions and a
    /// little context around them are rendered.
    @Test("a hunk carries context around the change but not the whole file")
    func hunksAreLocal() throws {
        let original = (1...40).map(String.init).joined(separator: "\n")
        let proposed = original.replacingOccurrences(of: "\n20\n", with: "\ntwenty\n")

        let hunks = TextDiff.hunks(TextDiff.compare(original, to: proposed), context: 2)

        #expect(hunks.count == 1)
        let hunk = try #require(hunks.first)
        #expect(hunk.count < 12, "a 40-line file must not come back whole")
        #expect(hunk.contains { $0.text == "twenty" })
    }

    @Test("two distant changes are two hunks")
    func distantChangesStaySeparate() {
        let original = (1...60).map(String.init).joined(separator: "\n")
        var proposed = original.replacingOccurrences(of: "\n5\n", with: "\nfive\n")
        proposed = proposed.replacingOccurrences(of: "\n50\n", with: "\nfifty\n")

        #expect(TextDiff.hunks(TextDiff.compare(original, to: proposed), context: 2).count == 2)
    }

    /// Otherwise the same unchanged line appears at the end of one hunk and the
    /// start of the next, which reads as though it were duplicated in the file.
    @Test("nearby changes merge into a single hunk")
    func nearbyChangesMerge() {
        let original = (1...30).map(String.init).joined(separator: "\n")
        var proposed = original.replacingOccurrences(of: "\n10\n", with: "\nten\n")
        proposed = proposed.replacingOccurrences(of: "\n12\n", with: "\ntwelve\n")

        #expect(TextDiff.hunks(TextDiff.compare(original, to: proposed), context: 3).count == 1)
    }
}

/// A model's reply is prose with a file inside it. Pulling the file out wrongly
/// means writing prose, or half a file, over the user's code.
@Suite("Code block extraction")
struct CodeBlockTests {
    @Test("a fenced block is extracted without its fences")
    func extractsBlock() {
        let reply = """
        Here is the fix.

        ```swift
        let x = 1
        let y = 2
        ```
        """

        #expect(CodeBlock.extract(from: reply) == "let x = 1\nlet y = 2")
    }

    /// Explanations routinely quote the broken lines first and put the rewrite
    /// last, so taking the first block would write the bug back.
    @Test("the last block wins when the reply quotes code before rewriting it")
    func prefersTheLastBlock() {
        let reply = """
        The problem is here:

        ```
        broken
        ```

        Corrected:

        ```
        fixed
        ```
        """

        #expect(CodeBlock.extract(from: reply) == "fixed")
    }

    /// A truncated file written over the user's own is the worst outcome
    /// available, so an unterminated fence yields nothing at all.
    @Test("an unterminated fence is refused rather than taken to the end")
    func refusesUnterminatedFence() {
        let reply = """
        Here you go.

        ```swift
        let x = 1
        """

        #expect(CodeBlock.extract(from: reply) == nil)
    }

    @Test("a reply with no code block proposes nothing")
    func noBlockMeansNoProposal() {
        #expect(CodeBlock.extract(from: "I would not change anything here.") == nil)
        #expect(CodeBlock.extract(from: "") == nil)
    }

    @Test("an empty block is not a proposal to empty the file")
    func emptyBlockIsRefused() {
        #expect(CodeBlock.extract(from: "```\n\n```") == nil)
        #expect(CodeBlock.extract(from: "```swift\n```") == nil)
    }

    @Test("indentation inside the block is preserved exactly")
    func keepsIndentation() {
        let reply = "```\nfunc a() {\n    return 1\n}\n```"

        #expect(CodeBlock.extract(from: reply) == "func a() {\n    return 1\n}")
    }
}

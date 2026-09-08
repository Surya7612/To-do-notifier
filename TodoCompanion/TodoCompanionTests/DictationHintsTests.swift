import Foundation
import Testing

@testable import TodoCompanion

/// Which words get offered to the recognizer as likely to be said.
///
/// Worth testing because both failure modes are invisible: too few and the
/// feature does nothing, too many and the budget is spent on words that were
/// never going to be misheard, which dilutes the ones that were. Nothing here
/// asserts recognition accuracy — that is Apple's model, not this logic.
@Suite("Words the recognizer is told to expect")
struct DictationHintsTests {
    private func hints(_ screen: String, projects: [String] = []) -> [String] {
        DictationHints.from(screenText: screen, projectNames: projects)
    }

    @Test("identifiers with an interior capital are the point of the feature")
    func interiorCapitalsAreKept() {
        // The words a general English model splits in two: "Swift data",
        // "fair light". These are why the list exists.
        let found = hints("Open SwiftData and check the Fairlight tab in DaVinci")
        #expect(found.contains("SwiftData"))
        #expect(found.contains("DaVinci"))
    }

    @Test("ordinary capitalised words are not worth a slot")
    func ordinaryWordsAreDropped() {
        // OCR produces these in bulk, since every line of UI text starts with
        // a capital. Biasing towards "Window" helps nothing.
        let found = hints("Window Settings Search Delete This That")
        #expect(found.isEmpty)
    }

    @Test("words with digits in them are distinctive")
    func alphanumericsAreKept() {
        #expect(hints("running qwen3 locally").contains("qwen3"))
    }

    @Test("very short and very long tokens are skipped")
    func lengthIsBounded() {
        let long = String(repeating: "a", count: DictationHints.maximumLength + 5)
        let found = hints("AbC \(long)X")

        #expect(!found.contains("AbC"), "too short to be worth biasing")
        #expect(!found.contains { $0.count > DictationHints.maximumLength })
    }

    @Test("project names come first and are never truncated away")
    func projectNamesOutrankTheScreen() throws {
        // The user named these themselves, so they are coinages by definition
        // and are the least likely thing in any general vocabulary.
        let screen = (1...200).map { "ScreenWord\($0)" }.joined(separator: " ")
        let found = hints(screen, projects: ["Engram"])

        #expect(found.first == "Engram")
        #expect(found.count <= DictationHints.limit)
    }

    @Test("the list is capped, since a long one dilutes every entry")
    func listIsCapped() {
        let many = (1...500).map { "TokenNumber\($0)" }.joined(separator: " ")
        #expect(hints(many).count == DictationHints.limit)
    }

    @Test("interior capitals are kept in preference to plain capitals")
    func distinctiveWordsSurviveTruncation() throws {
        // Ordering matters only because the list is cut. What is cut should be
        // the ordinary noun, not the identifier.
        let alphabet = "abcdefghijklmnopqrstuvwxyz"
        let plain = alphabet.flatMap { first in
            alphabet.map { second in "\(first.uppercased())\(second)oon" }
        }
        .prefix(DictationHints.limit)
        .joined(separator: " ")
        let found = hints("\(plain) NeuralEngine")

        #expect(found.contains("NeuralEngine"))
    }

    @Test("the same word twice takes one slot")
    func duplicatesCollapse() {
        let found = hints("SwiftData SwiftData swiftdata")
        #expect(found.count == 1)
    }

    @Test("nothing on screen means nothing to expect")
    func emptyScreenYieldsNothing() {
        #expect(hints("").isEmpty)
        #expect(hints("   \n  ").isEmpty)
    }

    @Test("a blank project name is not offered as a word")
    func blankProjectNamesAreIgnored() {
        #expect(hints("", projects: ["", "   "]).isEmpty)
    }
}

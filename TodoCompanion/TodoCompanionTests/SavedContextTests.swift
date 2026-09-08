import Carbon.HIToolbox
import Foundation
import Testing
@testable import TodoCompanion

/// Tagging happens by typing `#thing` in the same sentence as the reason for
/// saving, so the splitter runs on every save and its mistakes are permanent.
@Suite("Hashtags and saved context")
struct SavedContextTests {
    @Test("a tag is pulled out and the sentence keeps the rest")
    func splitsTagFromSentence() {
        let (text, topics) = "compare this to #engram later".splittingHashtags()

        #expect(text == "compare this to later")
        #expect(topics == ["engram"])
    }

    @Test("tags are lowercased so they match regardless of typing")
    func tagsAreCaseInsensitive() {
        #expect("read #Engram".splittingHashtags().topics == ["engram"])
    }

    @Test("trailing punctuation is not part of the tag")
    func stripsPunctuation() {
        #expect("look at #retrieval, then stop".splittingHashtags().topics == ["retrieval"])
    }

    @Test("several tags all come through")
    func handlesMultipleTags() {
        let (text, topics) = "#swift #macos figure this out".splittingHashtags()

        #expect(topics == ["swift", "macos"])
        #expect(text == "figure this out")
    }

    @Test("a bare hash is not a tag")
    func ignoresLoneHash() {
        let (text, topics) = "issue # 42".splittingHashtags()

        #expect(topics.isEmpty)
        #expect(text == "issue # 42")
    }

    /// Someone who types only tags still meant to say something, so the
    /// original sentence is kept rather than storing an empty reason.
    @Test("a sentence of nothing but tags keeps its original text")
    func keepsTextWhenOnlyTags() {
        let (text, topics) = "#engram #retrieval".splittingHashtags()

        #expect(topics == ["engram", "retrieval"])
        #expect(text == "#engram #retrieval")
    }

    @Test("text with no tags is returned unchanged")
    func passesThroughUntaggedText() {
        let (text, topics) = "just a plain reason".splittingHashtags()

        #expect(text == "just a plain reason")
        #expect(topics.isEmpty)
    }

    @Test("the search haystack covers every field worth searching")
    func haystackIncludesEverything() {
        let context = SavedContext(intent: "why I saved it",
                                   recognizedText: "text from the screen",
                                   sourceApp: "Safari",
                                   windowTitle: "A page title",
                                   topics: ["engram"])
        context.aiSummary = "a model's gloss"

        for expected in ["why I saved it", "text from the screen", "Safari", "A page title", "engram", "a model's gloss"] {
            #expect(context.searchHaystack.contains(expected))
        }
    }

    @Test("provenance degrades gracefully when the source is unknown")
    func provenanceHandlesMissingSource() {
        #expect(SavedContext(intent: "x", sourceApp: "Xcode", windowTitle: "Brain.swift").provenanceLabel
                == "Xcode — Brain.swift")
        #expect(SavedContext(intent: "x", sourceApp: "Xcode").provenanceLabel == "Xcode")
        #expect(SavedContext(intent: "x").provenanceLabel == "Unknown source")
    }
}

/// The summon shortcut is only useful if it is one macOS has not already
/// claimed, and a reserved combo fails silently rather than erroring.
@Suite("Hotkey choices")
struct HotkeyChoiceTests {
    @Test("an unknown or missing saved id falls back rather than losing the hotkey")
    func fallsBackForUnknownIdentifiers() {
        #expect(HotkeyChoice.named(nil).id == HotkeyChoice.fallback.id)
        #expect(HotkeyChoice.named("deleted-option").id == HotkeyChoice.fallback.id)
    }

    @Test("a saved id round-trips")
    func resolvesKnownIdentifiers() {
        for choice in HotkeyChoice.all {
            #expect(HotkeyChoice.named(choice.id) == choice)
        }
    }

    @Test("identifiers are unique so settings cannot resolve ambiguously")
    func identifiersAreUnique() {
        #expect(Set(HotkeyChoice.all.map(\.id)).count == HotkeyChoice.all.count)
    }

    /// ⌘Space, ⌥⌘Space and ⌃⌘Space are taken by Spotlight, the Finder search
    /// window and the Character Viewer. The system eats them before a Carbon
    /// hot key sees them, while registration still reports success.
    @Test("no offered combo is one macOS reserves")
    func avoidsReservedCombinations() {
        let reserved: Set<UInt32> = [
            UInt32(cmdKey),
            UInt32(optionKey | cmdKey),
            UInt32(controlKey | cmdKey),
        ]

        let spaceCombos = HotkeyChoice.all
            .filter { $0.keyCode == UInt32(kVK_Space) }
            .map(\.modifiers)

        #expect(!spaceCombos.isEmpty)
        #expect(spaceCombos.allSatisfy { !reserved.contains($0) })
    }
}

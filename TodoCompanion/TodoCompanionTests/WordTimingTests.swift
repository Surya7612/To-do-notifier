import Foundation
import Testing

@testable import TodoCompanion

/// Word timing decides the moment a box lands on a label while Max is
/// speaking. Wrong in one direction the box runs ahead of the voice, in the
/// other it trails it; both read as the pointing not following the speech,
/// which is the complaint this exists to answer.
@Suite("Word timing")
struct WordTimingTests {
    @Test("each written word starts where its phonemes start")
    func alignedWords() {
        // "ab cd": BOS(2) a(1) b(1) ␠(1) c(2) d(2) EOS(1) = 10 units over 1 s.
        let cues = WordTiming.cues(text: "ab cd",
                                   phonemes: "ab cd",
                                   durations: [2, 1, 1, 1, 2, 2, 1],
                                   totalSeconds: 1.0)
        #expect(cues.map(\.characterOffset) == [0, 3])
        #expect(abs(cues[0].seconds - 0.2) < 0.0001)
        #expect(abs(cues[1].seconds - 0.5) < 0.0001)
    }

    @Test("cues only ever move forwards through the sentence")
    func monotonic() {
        let text = "On \"put(1, 1)\" the cache fills, then \"get(1)\" refreshes it."
        let phonemes = "ɑn pʊt wʌn wʌn ðə kæʃ fɪlz ðɛn ɡɛt wʌn ɹɪfɹɛʃɪz ɪt"
        let durations = [Int32](repeating: 3, count: phonemes.count + 2)
        let cues = WordTiming.cues(text: text, phonemes: phonemes, durations: durations, totalSeconds: 4)
        #expect(cues.count == WordTiming.wordOffsets(in: text).count)
        #expect(zip(cues, cues.dropFirst()).allSatisfy { $0.seconds <= $1.seconds })
        #expect(cues.last.map { $0.seconds < 4 } == true)
    }

    @Test("a dropped phoneme falls back to spacing by length rather than nothing")
    func misalignedFallsBack() {
        let cues = WordTiming.cues(text: "one two", phonemes: "wʌn tu", durations: [1, 1], totalSeconds: 2)
        #expect(cues.map(\.characterOffset) == [0, 4])
        #expect(cues[0].seconds == 0)
        #expect(cues[1].seconds > 0 && cues[1].seconds < 2)
    }
}

@Suite("Label being heard")
struct LabelHeardTests {
    let piece = "First \"put(1, 1)\" fills it, then \"get(1)\" refreshes key 1."

    @Test("nothing is pointed at before the first quote is reached")
    func beforeFirstQuote() {
        #expect(Lesson.label(heardAt: 0, in: piece) == nil)
    }

    @Test("a label is reached from its opening quote, and held until the next")
    func reachedAndHeld() {
        let firstQuote = Array(piece).firstIndex(of: "\"")!
        #expect(Lesson.label(heardAt: firstQuote, in: piece) == "put(1, 1)")
        let then = piece.distance(from: piece.startIndex, to: piece.range(of: "then")!.lowerBound)
        #expect(Lesson.label(heardAt: then, in: piece) == "put(1, 1)")
        let second = piece.distance(from: piece.startIndex, to: piece.range(of: "\"get")!.lowerBound)
        #expect(Lesson.label(heardAt: second, in: piece) == "get(1)")
        #expect(Lesson.label(heardAt: piece.count - 1, in: piece) == "get(1)")
    }

    @Test("a label is found by its words once the voice has dropped its backticks")
    func withoutQuoteMarks() {
        // What `speakable` makes of "First `put(1, 1)` fills it, then `get(1)`…".
        let spoken = "First put(1, 1) fills it, then get(1) refreshes key 1."
        let labels = ["put(1, 1)", "get(1)"]
        #expect(Lesson.label(heardAt: 0, in: spoken, among: labels) == nil)
        #expect(Lesson.label(heardAt: 6, in: spoken, among: labels) == "put(1, 1)")
        let get = spoken.distance(from: spoken.startIndex, to: spoken.range(of: "get")!.lowerBound)
        let then = spoken.distance(from: spoken.startIndex, to: spoken.range(of: "then")!.lowerBound)
        #expect(Lesson.label(heardAt: then, in: spoken, among: labels) == "put(1, 1)")
        #expect(Lesson.label(heardAt: get, in: spoken, among: labels) == "get(1)")
    }
}

/// What the Kokoro voice is handed instead of the text as written. Every
/// failure is heard rather than seen — "LRU" read as "Leku" — and an offset
/// map that drifts would land every box on the wrong word, so both are pinned.
@Suite("Spoken form")
struct SpokenFormTests {
    @Test("acronyms are spelled out in letter names")
    func acronyms() {
        #expect(SpokenForm.of("An LRU cache").text == "An el ar you cache")
        #expect(SpokenForm.of("two APIs").text == "two ay pee eyes")
    }

    @Test("identifiers are split where a reader hears a new word")
    func identifiers() {
        #expect(SpokenForm.of("LRUCache").text == "el ar you Cache")
        #expect(SpokenForm.of("getValue").text == "get Value")
        #expect(SpokenForm.of("lRUCache").text == "el ar you Cache")
    }

    @Test("ordinary words survive, including ones a model shouts")
    func ordinaryWords() {
        let sentence = "Do NOT evict the key I just read, and keep a JSON copy."
        #expect(SpokenForm.of(sentence).text == "Do not evict the key I just read, and keep a jason copy.")
        #expect(SpokenForm.of("it's what we don't evict, e.g. key 1").text
                == "it's what we don't evict, for example key 1")
    }

    @Test("big O is said the way people say it")
    func bigO() {
        #expect(SpokenForm.of("Each call is O(1).").text == "Each call is big O of 1).")
    }

    @Test("every spoken character maps back into the written text, in order")
    func offsetsMapBack() {
        let written = "Call get(1) on the LRUCache now."
        let spoken = SpokenForm.of(written)
        #expect(spoken.originalOffset.count == spoken.text.count)
        #expect(zip(spoken.originalOffset, spoken.originalOffset.dropFirst()).allSatisfy { $0 <= $1 })
        let spokenNow = spoken.text.distance(from: spoken.text.startIndex,
                                             to: spoken.text.range(of: "now")!.lowerBound)
        let writtenNow = written.distance(from: written.startIndex, to: written.range(of: "now")!.lowerBound)
        #expect(spoken.writtenOffset(spokenNow) == writtenNow)
        let spokenCache = spoken.text.distance(from: spoken.text.startIndex,
                                               to: spoken.text.range(of: "el ar")!.lowerBound)
        let writtenCache = written.distance(from: written.startIndex,
                                            to: written.range(of: "LRUCache")!.lowerBound)
        #expect(spoken.writtenOffset(spokenCache) == writtenCache)
    }
}

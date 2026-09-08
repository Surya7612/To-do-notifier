import Foundation
import Testing

@testable import TodoCompanion

/// The one piece of the Kokoro voice that can be checked without loading a
/// model or opening an audio device.
///
/// It earns a test because the failure it guards is the worst kind available
/// here: macOS 26.4 and 26.5 carry an Apple bug that crashes Kokoro synthesis
/// inside libBNNS *intermittently*, so a wrong answer to this question does not
/// show up as a broken voice, it shows up as the whole app vanishing once in a
/// while. FluidAudio only logs a warning, which is why this app decides for
/// itself.
@Suite("Which systems the Kokoro voice will run on")
struct KokoroSupportTests {
    /// Mirrors `KokoroVoiceSynthesizer.isSupportedBySystem` against a stated
    /// version rather than the running one, since a test that asked the machine
    /// would assert whatever this Mac happens to be today.
    private func isSupported(major: Int, minor: Int) -> Bool {
        guard major == 26 else { return true }
        return minor < 4 || minor > 5
    }

    @Test("the two known-bad releases are refused")
    func crashProneReleasesAreRefused() {
        #expect(!isSupported(major: 26, minor: 4))
        #expect(!isSupported(major: 26, minor: 5))
    }

    @Test("the release that fixes the bug is allowed")
    func fixedReleaseIsAllowed() {
        #expect(isSupported(major: 26, minor: 6))
        #expect(isSupported(major: 26, minor: 7))
        #expect(isSupported(major: 27, minor: 0))
    }

    @Test("releases before the bug are allowed")
    func earlierReleasesAreAllowed() {
        #expect(isSupported(major: 26, minor: 0))
        #expect(isSupported(major: 26, minor: 3))
    }

    @Test("the running system agrees with the same rule")
    func matchesTheImplementation() {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #expect(KokoroVoiceSynthesizer.isSupportedBySystem
            == isSupported(major: version.majorVersion, minor: version.minorVersion))
    }
}

/// How a streaming answer is cut up before it is spoken.
///
/// This is the difference between a delivery that sounds like someone talking
/// and one that sounds like a station announcement, and none of it is audible
/// from the code. Kokoro synthesizes each piece separately, so every cut costs
/// an intonation reset and a pause; too few cuts and it exceeds what one
/// synthesis accepts, which is thrown away rather than spoken.
@Suite("Cutting an answer into things to say")
struct SpeechChunkingTests {
    private func chunk(_ text: String, allowingShort: Bool = false) -> String? {
        SpeechPlayback.nextChunk(in: text, allowingShort: allowingShort)
    }

    @Test("the first sentence goes out on its own, so speech starts early")
    func firstSentenceIsNotHeldBack() {
        let chunk = chunk("Here is the answer. ", allowingShort: true)
        #expect(chunk == "Here is the answer.")
    }

    @Test("later fragments are held until there is a clause worth shaping")
    func shortFragmentsAreAccumulated() {
        // Three words is exactly what made the delivery choppy: on its own it
        // gets a whole intonation contour and a pause at each end.
        #expect(chunk("Yes. ") == nil)
        #expect(chunk("Yes. It does. ") == nil)
    }

    @Test("once enough has arrived, it is cut at a sentence end")
    func cutsAtASentenceEnd() throws {
        let text = String(repeating: "This is a sentence of some length. ", count: 6)
        let spoken = try #require(chunk(text))

        #expect(spoken.count >= SpeechPlayback.minimumChunk)
        #expect(spoken.count <= SpeechPlayback.maximumChunk)
        #expect(spoken.hasSuffix("."), "a cut anywhere else is audible")
    }

    @Test("a decimal point is not a sentence end")
    func decimalsAreNotBoundaries() {
        // "The file is 3." then "5 megabytes" — the reason a period alone
        // cannot be the test.
        let text = "The download is 174.5 megabytes in total which is a fair amount of data to fetch"
        #expect(chunk(text, allowingShort: true) == nil)
    }

    @Test("a file name is not a sentence end")
    func fileExtensionsAreNotBoundaries() {
        #expect(chunk("Look at Brain.swift", allowingShort: true) == nil)
    }

    @Test("a newline ends a line even with no punctuation")
    func newlinesAreBoundaries() throws {
        // Lists arrive this way, and each item really is its own utterance.
        let spoken = try #require(chunk("First item\nSecond item\n", allowingShort: true))
        #expect(spoken == "First item\n")
    }

    @Test("a colon is not a boundary, since it introduces what follows")
    func colonsAreNotBoundaries() {
        #expect(chunk("The problem is this: ", allowingShort: true) == nil)
    }

    @Test("nothing is ever handed over longer than one synthesis accepts")
    func neverExceedsTheSynthesisLimit() throws {
        // Kokoro throws on an over-long phoneme sequence and the clause is
        // dropped, so an unbounded chunk is silently unspoken text.
        let oneLongSentence = String(repeating: "word ", count: 200)
        let spoken = try #require(chunk(oneLongSentence))

        #expect(spoken.count <= SpeechPlayback.maximumChunk)
        #expect(!spoken.isEmpty, "an empty chunk would spin the caller's loop")
    }

    @Test("a sentence longer than the limit is broken at a word gap")
    func overLongSentenceBreaksAtAWord() throws {
        let spoken = try #require(chunk(String(repeating: "alpha ", count: 100)))
        #expect(spoken.hasSuffix("alpha"), "not mid-word")
    }

    @Test("an empty answer asks for nothing to be said")
    func emptyTextYieldsNothing() {
        #expect(chunk("", allowingShort: true) == nil)
    }
}

/// The join between two spoken sentences.
///
/// Pure sample arithmetic, and the one part of why the delivery sounded
/// mechanical that can be checked without listening to it.
@Suite("Joining one clause to the next")
struct SpeechPacingTests {
    private let sampleRate = 24_000.0

    private func trimmed(_ samples: [Float]) -> [Float] {
        KokoroVoiceSynthesizer.trimmedWithTail(samples, sampleRate: sampleRate)
    }

    @Test("the model's own padding is cut from both ends")
    func paddingIsRemoved() {
        let padding = [Float](repeating: 0, count: 2_400)
        let speech: [Float] = [0.4, -0.5, 0.4]
        let result = trimmed(padding + speech + padding)

        // What is left is the speech plus one deliberate tail, so the leading
        // padding is gone entirely and the trailing padding is replaced.
        #expect(result.prefix(3) == speech[...])
        #expect(result.count < (padding + speech + padding).count)
    }

    @Test("a consistent tail is added, not inherited")
    func tailIsTheSameWhateverThePadding() {
        let speech: [Float] = [0.4, -0.5, 0.4]
        let withNoPadding = trimmed(speech)
        let withLotsOfPadding = trimmed(speech + [Float](repeating: 0, count: 9_000))

        // Sentences ran together when the tail came from the model, because
        // some clauses arrive with almost no padding at all.
        #expect(withNoPadding.count == withLotsOfPadding.count)
        #expect(withNoPadding.count > speech.count, "there has to be a pause")
    }

    @Test("silence is not scheduled at all")
    func silenceYieldsNothing() {
        // An empty buffer handed to the player would still count as something
        // playing, so the stop button would stay lit with nothing to stop.
        #expect(trimmed([Float](repeating: 0, count: 4_800)).isEmpty)
        #expect(trimmed([]).isEmpty)
    }

    @Test("quiet speech is not mistaken for silence")
    func lowVolumeSpeechSurvives() {
        // The floor is above zero because the model's output does not sit at
        // exactly zero between words; it must still be well below real speech.
        #expect(!trimmed([0.02, -0.03, 0.02]).isEmpty)
    }
}

@Suite("Choosing a voice")
struct VoiceEngineSettingTests {
    @Test("the system voice is the default, since it needs no download")
    func defaultsToTheSystemVoice() {
        #expect(AppSettings.VoiceEngine(rawValue: "") == nil)
        #expect(AppSettings.VoiceEngine(rawValue: "nonsense") == nil)
    }

    @Test("every engine names itself and says what the trade is")
    func everyEngineIsDescribed() {
        for engine in AppSettings.VoiceEngine.allCases {
            #expect(!engine.displayName.isEmpty)
            #expect(!engine.detail.isEmpty)
        }
    }

    @Test("neither option is a hosted service")
    func neitherVoiceLeavesTheMachine() {
        // The ban on cloud speech synthesis is the reason this picker has two
        // entries rather than three. Pins the promise the Settings copy makes.
        let described = AppSettings.VoiceEngine.allCases
            .map(\.detail)
            .joined(separator: " ")
            .lowercased()
        for hosted in ["openai", "elevenlabs", "cloud", "api", "server"] {
            #expect(!described.contains(hosted))
        }
    }
}

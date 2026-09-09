import AVFoundation
import Foundation

/// Reads answers aloud, on this Mac.
///
/// The project forbids cloud transcription and the same reasoning applies in
/// reverse: routing every answer through a speech vendor would export the
/// contents of the user's screen to a third party that is not even answering
/// the question. Both available voices run here — see `AppSettings.VoiceEngine`
/// — and neither may be swapped for a hosted one.
///
/// This type decides *what* is spoken and *when*; a `VoiceSynthesizer` says it.
@MainActor
@Observable
final class SpeechPlayback {
    private var synthesizer: (any VoiceSynthesizer)?
    private var synthesizerEngine: AppSettings.VoiceEngine?

    private(set) var isSpeaking = false

    /// Called with each clause as it starts being heard, and with nil when the
    /// voice falls silent. Both halves matter to a caller that is showing
    /// something alongside the speech: without the nil it has no idea when to
    /// take it down again.
    var onSpeakingClause: (@MainActor (String?) -> Void)?

    /// Surfaced when a chosen voice could not be used at all, so a silent
    /// answer has a stated reason rather than looking like a dead setting.
    private(set) var failure: String?

    /// Text already handed to the voice, so streaming enqueues only what is new.
    private var spokenPrefixLength = 0

    /// Clauses that arrived while a model was still loading.
    private var heldClauses: [String] = []

    /// The one in-flight model load, so clauses do not each start their own.
    private var preparation: Task<Void, Never>?

    /// Kept between answers so a model is loaded once rather than per question.
    private func voice() -> any VoiceSynthesizer {
        let engine = AppSettings.voiceEngine
        if engine != synthesizerEngine || synthesizer == nil {
            synthesizer?.stop()
            synthesizer = engine.makeSynthesizer()
            synthesizerEngine = engine
            synthesizer?.onFinishedSpeaking = { [weak self] in
                self?.isSpeaking = false
                self?.onSpeakingClause?(nil)
            }
            synthesizer?.onStartedSpeaking = { [weak self] clause in
                self?.onSpeakingClause?(clause)
            }
        }
        // Safe: `makeSynthesizer` always returns one.
        return synthesizer ?? SystemVoiceSynthesizer()
    }

    /// True when the next answer has a model to load, which the panel explains.
    var willLoadModel: Bool {
        let engine = AppSettings.voiceEngine
        guard engine != .system else { return false }
        guard engine == synthesizerEngine, let synthesizer else { return true }
        return !synthesizer.isPrepared
    }

    /// Enough text for the voice to shape a clause rather than a fragment.
    ///
    /// The first piece of an answer is sent as soon as a sentence ends, because
    /// that is what makes speech start about a second after the model does.
    /// Everything after it is accumulated to this length first. Kokoro
    /// synthesizes each piece independently, so a three-word fragment arrives
    /// with its own intonation contour and its own silence at both ends, and a
    /// paragraph delivered as eight of those sounds like a sequence of
    /// announcements rather than someone speaking.
    static let minimumChunk = 140

    /// Kokoro rejects a phoneme sequence longer than 510 characters outright,
    /// and a rejected piece is dropped rather than spoken, so text is broken up
    /// before that can happen. Well below the limit, because phonemes are not
    /// characters and the ratio depends on the words.
    static let maximumChunk = 300

    /// Enqueues whatever has become speakable since the last call.
    func speakArriving(_ text: String) {
        guard AppSettings.speaksAnswers else { return }

        var pending = String(text.dropFirst(spokenPrefixLength))
        while let chunk = Self.nextChunk(in: pending,
                                         allowingShort: spokenPrefixLength == 0),
              !chunk.isEmpty {
            spokenPrefixLength += chunk.count
            pending = String(pending.dropFirst(chunk.count))
            enqueue(chunk)
        }
    }

    /// Speaks whatever is left once the stream has finished, including a final
    /// fragment with no terminating punctuation.
    func finish(_ text: String) {
        guard AppSettings.speaksAnswers else { return }

        var remainder = String(text.dropFirst(spokenPrefixLength))
        spokenPrefixLength = text.count

        // Still broken up: the tail can be longer than one synthesis accepts.
        while remainder.count > Self.maximumChunk,
              let chunk = Self.nextChunk(in: remainder, allowingShort: true),
              !chunk.isEmpty {
            remainder = String(remainder.dropFirst(chunk.count))
            enqueue(chunk)
        }
        enqueue(remainder)
    }

    /// The next stretch of text worth speaking, or `nil` while there is not yet
    /// enough of it to be worth interrupting the flow for.
    ///
    /// Pure, so the sizing is testable without a voice or an audio device.
    static func nextChunk(in pending: String, allowingShort: Bool) -> String? {
        let minimum = allowingShort ? 1 : minimumChunk
        let boundaries = sentenceBoundaries(in: pending)

        // The first sentence end that gives the voice a full clause to work
        // with, and still fits in one synthesis.
        if let boundary = boundaries.first(where: { $0 >= minimum && $0 <= maximumChunk }) {
            return String(pending.prefix(boundary))
        }

        // Otherwise wait for more text — unless waiting would overrun the cap.
        guard pending.count > maximumChunk else { return nil }

        if let boundary = boundaries.last(where: { $0 <= maximumChunk }) {
            return String(pending.prefix(boundary))
        }

        // One sentence longer than a whole synthesis has to be broken
        // somewhere, and a word gap is the least bad place. Reached by things
        // that are punctuated as prose but written as a list.
        let capped = pending.prefix(maximumChunk)
        guard let lastSpace = capped.lastIndex(of: " ") else { return String(capped) }
        return String(capped[..<lastSpace])
    }

    /// Offsets just past each sentence ending, in order.
    ///
    /// A colon is deliberately not one. It introduces the clause that follows
    /// it, so speaking the two sides separately puts the pause in the wrong
    /// place — "the problem is:" then, after a beat, the actual answer.
    private static func sentenceBoundaries(in text: String) -> [Int] {
        var boundaries: [Int] = []
        let characters = Array(text)

        for (offset, character) in characters.enumerated() {
            let next = offset + 1

            switch character {
            case "\n", "!", "?":
                boundaries.append(next)
            case ".":
                // A period only ends a sentence when a gap follows it,
                // otherwise every decimal point and file extension is one —
                // "3." then "5 megabytes", "Brain." then "swift".
                guard next == characters.count || characters[next].isWhitespace else { continue }
                boundaries.append(next)
            default:
                continue
            }
        }
        return boundaries
    }

    func stop() {
        spokenPrefixLength = 0
        isSpeaking = false
        onSpeakingClause?(nil)
        // A load in flight is deliberately left running: it is the expensive
        // part, it is what the next answer needs, and cancelling it halfway
        // through a download buys nothing.
        heldClauses = []
        synthesizer?.stop()
    }

    private func enqueue(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let voice = voice()
        let spoken = spoken(from: trimmed)
        guard !spoken.isEmpty else { return }

        // Prepared lazily rather than at launch: a voice nobody switches on
        // should not load a model, and the system voice has nothing to load.
        guard voice.isPrepared else {
            // Held rather than spoken late one clause at a time, and held
            // rather than dropped, so the first answer after switching Kokoro
            // on is read out once the model is up instead of being the one
            // answer that silently is not.
            heldClauses.append(spoken)
            prepare(voice)
            return
        }

        voice.enqueue(spoken)
        isSpeaking = true
    }

    /// Loads the voice's model, once.
    ///
    /// Guarded because clauses arrive several to an answer: without this each
    /// one started its own load of the same model, which on a first run means
    /// several concurrent downloads of the same 174 MB.
    private func prepare(_ voice: any VoiceSynthesizer) {
        guard preparation == nil else { return }

        preparation = Task {
            defer { preparation = nil }

            do {
                try await voice.prepare()
                failure = nil
            } catch {
                failure = error.localizedDescription
                NSLog("[Voice] \(error.localizedDescription)")
                heldClauses = []
                return
            }

            let held = heldClauses
            heldClauses = []
            guard AppSettings.speaksAnswers, !held.isEmpty else { return }

            for clause in held { voice.enqueue(clause) }
            isSpeaking = true
        }
    }

    /// Strips markup that is meant to be read with the eyes.
    ///
    /// Without this the voice pronounces every asterisk and backtick, and a
    /// fenced code block is read out character by character — which is both
    /// unbearable and long enough that the user cannot interrupt it easily.
    private func spoken(from text: String) -> String {
        var result = ""
        var insideFence = false

        for line in text.components(separatedBy: .newlines) {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if !insideFence { result += "Code block. " }
                insideFence.toggle()
                continue
            }
            guard !insideFence else { continue }

            result += line.filter { !"*_`#>|".contains($0) } + " "
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

}

extension SpeechPlayback {
    /// System voices offered in Settings.
    ///
    /// Filtered to the user's own language, because the full list is hundreds
    /// of entries across dozens of locales and picking a voice that cannot
    /// pronounce the answer is the main way this setting goes wrong.
    static var availableVoices: [AVSpeechSynthesisVoice] {
        let language = AVSpeechSynthesisVoice.currentLanguageCode()
        let prefix = String(language.prefix(2))

        return AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix(prefix) }
            .sorted { $0.name < $1.name }
    }
}

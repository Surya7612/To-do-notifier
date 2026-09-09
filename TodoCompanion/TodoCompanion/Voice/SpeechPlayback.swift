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
        consume(Self.speakable(from: text), toTheEnd: false)
    }

    /// Speaks whatever is left once the stream has finished, including a final
    /// fragment with no terminating punctuation.
    func finish(_ text: String) {
        guard AppSettings.speaksAnswers else { return }
        consume(Self.speakable(from: text), toTheEnd: true)
    }

    /// Sends on whatever of the speakable text has not been sent yet.
    ///
    /// Note what is passed in: the *whole* answer, stripped, every time. Markup
    /// used to be removed from each chunk just before it was spoken, and the
    /// consequence was the worst bug in this file — a fence is opened on one
    /// chunk and closed on another, so a chunk starting inside a code block
    /// began with `insideFence` false and the voice read the code out, bracket
    /// by bracket. Stripping the document rather than the fragment is the only
    /// way the state can be right, because the state is a property of the
    /// document.
    private func consume(_ speakable: String, toTheEnd: Bool) {
        var pending = String(speakable.dropFirst(spokenPrefixLength))

        while let chunk = Self.nextChunk(in: pending,
                                         allowingShort: spokenPrefixLength == 0),
              !chunk.isEmpty {
            spokenPrefixLength += chunk.count
            pending = String(pending.dropFirst(chunk.count))
            enqueue(chunk)
        }

        guard toTheEnd, !pending.isEmpty else { return }
        spokenPrefixLength = speakable.count

        // Still broken up: the tail can be longer than one synthesis accepts.
        while pending.count > Self.maximumChunk,
              let chunk = Self.nextChunk(in: pending, allowingShort: true),
              !chunk.isEmpty {
            pending = String(pending.dropFirst(chunk.count))
            enqueue(chunk)
        }
        enqueue(pending)
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
        let spoken = trimmed

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

    /// The answer with everything that is meant for the eyes taken out.
    ///
    /// Pure and given the whole document, so it is testable and so the fence
    /// state is right — see `consume`.
    ///
    /// Lines are joined with newlines rather than spaces because `nextChunk`
    /// treats a line ending as a place it may break, and a list whose items
    /// carry no full stops has no other one.
    static func speakable(from text: String) -> String {
        var lines: [String] = []
        var insideFence = false

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                // Announced, not read. A function read out character by
                // character is unbearable and too long to interrupt.
                if !insideFence { lines.append("Code block.") }
                insideFence.toggle()
                continue
            }
            guard !insideFence else { continue }

            let spoken = spokenLine(trimmed)
            if !spoken.isEmpty { lines.append(spoken) }
        }

        return lines.joined(separator: "\n")
    }

    /// One line of prose, without the characters that are punctuation to a
    /// reader and noise to a listener.
    private static func spokenLine(_ line: String) -> String {
        var withoutMarkers = line
        for marker in ["- ", "* ", "+ ", "• ", "> "] where withoutMarkers.hasPrefix(marker) {
            withoutMarkers = String(withoutMarkers.dropFirst(marker.count))
            break
        }

        var result = ""
        var span = ""
        var insideCode = false

        func closeSpan() {
            // An inline span with no word in it is a symbol being *shown* —
            // "`(` was never closed" — and a synthesizer either skips it or
            // says "left parenthesis" in the middle of a sentence about it.
            // Either way the sentence is better without it.
            if span.contains(where: { $0.isLetter || $0.isNumber }) { result += span }
            span = ""
        }

        for character in withoutMarkers {
            if character == "`" {
                if insideCode { closeSpan() }
                insideCode.toggle()
                continue
            }
            if insideCode {
                span.append(character)
                continue
            }
            guard !"*_#|".contains(character) else { continue }
            result.append(character)
        }

        // A span still open is the stream stopping mid-word, not a mistake.
        if insideCode { closeSpan() }

        return Self.withoutMath(result)
            .split(separator: " ", omittingEmptySubsequences: true)
            .joined(separator: " ")
    }

    /// Removes the delimiters of a LaTeX expression.
    ///
    /// `Prompt.formatting` asks for mathematics in plain words, and this is the
    /// belt to that pair of braces: a model that reaches for LaTeX anyway
    /// produces `\(O(n \cdot 2^n)\)`, which is read out as a string of
    /// backslashes and letters. Only the delimiters go, because what is between
    /// them is at least the right symbols in the right order.
    private static func withoutMath(_ text: String) -> String {
        var result = text
        for delimiter in ["\\(", "\\)", "\\[", "\\]"] {
            result = result.replacingOccurrences(of: delimiter, with: "")
        }
        return result
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

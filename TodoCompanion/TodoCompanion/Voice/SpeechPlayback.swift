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

    /// Surfaced when a chosen voice could not be used at all, so a silent
    /// answer has a stated reason rather than looking like a dead setting.
    private(set) var failure: String?

    /// Text already handed to the voice, so streaming enqueues only what is new.
    private var spokenPrefixLength = 0

    /// Kept between answers so a model is loaded once rather than per question.
    private func voice() -> any VoiceSynthesizer {
        let engine = AppSettings.voiceEngine
        if engine != synthesizerEngine || synthesizer == nil {
            synthesizer?.stop()
            synthesizer = engine.makeSynthesizer()
            synthesizerEngine = engine
            synthesizer?.onFinishedSpeaking = { [weak self] in
                self?.isSpeaking = false
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

    /// Enqueues any complete sentences that have arrived since the last call.
    ///
    /// Sentence at a time rather than waiting for the whole answer, so speech
    /// starts within a second of the model starting — and rather than word at a
    /// time, because prosody depends on having a full clause and per-word
    /// utterances come out as a stilted list. Kokoro needs the clause for a
    /// second reason: it synthesizes one at a time, so a clause is also the
    /// unit of work that overlaps generation with playback.
    func speakArriving(_ text: String) {
        guard AppSettings.speaksAnswers else { return }

        let pending = String(text.dropFirst(spokenPrefixLength))
        guard let boundary = lastSentenceBoundary(in: pending) else { return }

        let ready = String(pending[..<boundary])
        spokenPrefixLength += ready.count
        enqueue(ready)
    }

    /// Speaks whatever is left once the stream has finished, including a final
    /// fragment with no terminating punctuation.
    func finish(_ text: String) {
        guard AppSettings.speaksAnswers else { return }

        let remainder = String(text.dropFirst(spokenPrefixLength))
        spokenPrefixLength = text.count
        enqueue(remainder)
    }

    func stop() {
        spokenPrefixLength = 0
        isSpeaking = false
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
            Task {
                do {
                    try await voice.prepare()
                    failure = nil
                    guard AppSettings.speaksAnswers else { return }
                    voice.enqueue(spoken)
                    isSpeaking = true
                } catch {
                    failure = error.localizedDescription
                    NSLog("[Voice] \(error.localizedDescription)")
                }
            }
            return
        }

        voice.enqueue(spoken)
        isSpeaking = true
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

    /// The index just past the last sentence-ending punctuation.
    private func lastSentenceBoundary(in text: String) -> String.Index? {
        guard let position = text.lastIndex(where: { ".!?\n:".contains($0) }) else { return nil }
        return text.index(after: position)
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

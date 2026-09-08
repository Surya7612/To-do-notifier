import AVFoundation
import Foundation

/// Reads answers aloud, on this Mac.
///
/// `AVSpeechSynthesizer` rather than a hosted voice. The project forbids cloud
/// transcription and the same reasoning applies in reverse: routing every
/// answer through a speech vendor would export the contents of the user's
/// screen to a third party that is not even answering the question. The system
/// voices are less impressive than a hosted one, and they are free, offline,
/// need no entitlement, and work on a plane.
@MainActor
@Observable
final class SpeechPlayback {
    /// Replaced rather than reused after being stopped. See `stop()`.
    private var synthesizer = AVSpeechSynthesizer()

    /// Retained across synthesizers, since `delegate` is weak and a monitor
    /// owned only by the synthesizer would deallocate on replacement.
    private let monitor = UtteranceMonitor()

    private(set) var isSpeaking = false

    /// Text already handed to the synthesizer, so streaming can enqueue only
    /// what is new.
    private var spokenPrefixLength = 0

    init() {
        monitor.onQueueDrained = { [weak self] in
            guard let self else { return }
            // Asks the synthesizer rather than assuming: sentences are enqueued
            // as they stream, so one utterance finishing does not mean silence.
            isSpeaking = synthesizer.isSpeaking
        }
        synthesizer.delegate = monitor
    }

    /// Enqueues any complete sentences that have arrived since the last call.
    ///
    /// Sentence at a time rather than waiting for the whole answer, so speech
    /// starts within a second of the model starting — and rather than word at a
    /// time, because the synthesizer's prosody depends on having a full clause
    /// and per-word utterances come out as a stilted list.
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

        // Stopping an *idle* synthesizer wedges it: every later `speak` is
        // accepted and silently never heard. This is called at the top of every
        // question, so the unconditional version meant answers were never
        // spoken at all — the setting appeared to do nothing.
        guard synthesizer.isSpeaking || synthesizer.isPaused else { return }

        // `.immediate` rather than `.word`: this is called when the user asks
        // something new or starts dictating, and finishing the current word
        // would talk over them.
        synthesizer.stopSpeaking(at: .immediate)

        // A stopped synthesizer is replaced rather than reused. Whether it
        // recovers is undocumented and evidently version-dependent, and a fresh
        // one costs nothing next to an answer that is never read out.
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = monitor
    }

    private func enqueue(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: spoken(from: trimmed))
        if let identifier = AppSettings.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    /// Reports when the synthesizer stops having anything to say.
    ///
    /// Without it `isSpeaking` only ever went true, so the stop button in the
    /// panel header stayed lit after the answer had finished being read.
    private final class UtteranceMonitor: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
        var onQueueDrained: (@MainActor () -> Void)?

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                               didFinish utterance: AVSpeechUtterance) {
            report()
        }

        func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                               didCancel utterance: AVSpeechUtterance) {
            report()
        }

        /// The delegate makes no promise about which queue it calls on.
        private func report() {
            let callback = onQueueDrained
            Task { @MainActor in callback?() }
        }
    }

    /// Strips markup that is meant to be read with the eyes.
    ///
    /// Without this the synthesizer pronounces every asterisk and backtick, and
    /// a fenced code block is read out character by character — which is both
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
    /// Voices offered in Settings.
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

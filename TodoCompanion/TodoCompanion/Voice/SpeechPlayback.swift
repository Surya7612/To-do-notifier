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
    private let synthesizer = AVSpeechSynthesizer()

    private(set) var isSpeaking = false

    /// Text already handed to the synthesizer, so streaming can enqueue only
    /// what is new.
    private var spokenPrefixLength = 0

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
        // `.immediate` rather than `.word`: this is called when the user asks
        // something new or starts dictating, and finishing the current word
        // would talk over them.
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        spokenPrefixLength = 0
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

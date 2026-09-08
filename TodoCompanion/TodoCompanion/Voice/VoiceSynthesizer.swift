import AVFoundation
import Foundation

/// Turns a piece of an answer into sound.
///
/// Split out of `SpeechPlayback` so the voice can be swapped without touching
/// the part that decides *what* gets spoken and when. Breaking a streaming
/// answer into clauses and stripping markup out of it is the same work whoever
/// says the words.
@MainActor
protocol VoiceSynthesizer: AnyObject {
    var isSpeaking: Bool { get }

    /// Called when there is nothing left to say, so the stop button in the
    /// panel header can go out. Without it `isSpeaking` only ever went true.
    var onFinishedSpeaking: (@MainActor () -> Void)? { get set }

    /// Model loading, where there is any. Throws so a voice that cannot be used
    /// says why instead of producing silence.
    func prepare() async throws

    /// False when `prepare` still has real work to do.
    var isPrepared: Bool { get }

    /// Speaks this text after anything already queued.
    func enqueue(_ text: String)

    func stop()
}

/// Why a voice could not speak.
enum VoiceFailure: LocalizedError {
    case modelUnavailable(String)
    case unsupportedSystemVersion(String)
    case playbackFailed(String)

    var errorDescription: String? {
        switch self {
        case let .modelUnavailable(detail):
            "Couldn't load the Kokoro voice: \(detail). Pick the system voice in Settings."
        case let .unsupportedSystemVersion(version):
            "The Kokoro voice needs macOS 26.6 or later; this Mac is on \(version). "
                + "Pick the system voice in Settings."
        case let .playbackFailed(detail):
            "Couldn't play the answer: \(detail)."
        }
    }
}

/// The voices built into macOS, through `AVSpeechSynthesizer`.
///
/// Free, offline, needs no entitlement and works on a plane. It is also plainly
/// the more robotic of the two, which is why there is a second one.
@MainActor
final class SystemVoiceSynthesizer: VoiceSynthesizer {
    /// Replaced rather than reused after being stopped. See `stop()`.
    private var synthesizer = AVSpeechSynthesizer()

    /// Retained across synthesizers, since `delegate` is weak and a monitor
    /// owned only by the synthesizer would deallocate on replacement.
    private let monitor = UtteranceMonitor()

    private(set) var isSpeaking = false
    var onFinishedSpeaking: (@MainActor () -> Void)?

    /// Nothing to load.
    let isPrepared = true

    init() {
        monitor.onQueueDrained = { [weak self] in
            guard let self else { return }
            // Asks the synthesizer rather than assuming: sentences are enqueued
            // as they stream, so one utterance finishing does not mean silence.
            isSpeaking = synthesizer.isSpeaking
            if !isSpeaking { onFinishedSpeaking?() }
        }
        synthesizer.delegate = monitor
    }

    func prepare() async throws {}

    func enqueue(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        if let identifier = AppSettings.voiceIdentifier,
           let voice = AVSpeechSynthesisVoice(identifier: identifier) {
            utterance.voice = voice
        }
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    func stop() {
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

    /// Reports when the synthesizer stops having anything to say.
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
}

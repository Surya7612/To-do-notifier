import AVFoundation
import Foundation
import Speech

/// Why dictation could not start.
///
/// Shared by the microphone and both recognizers, because from the panel's side
/// they are the same event: the button was pressed and no words are coming.
enum DictationFailure: LocalizedError {
    case micDenied
    case speechDenied
    case recognizerUnavailable
    case noInputDevice
    case engineFailed(String)
    case modelUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .micDenied:
            "Microphone access is off. Enable it in System Settings → Privacy & Security → Microphone."
        case .speechDenied:
            "Speech Recognition is off. Enable it in System Settings → Privacy & Security → Speech Recognition."
        case .recognizerUnavailable:
            "Speech recognition isn't available for this language right now."
        case .noInputDevice:
            "No microphone input available. Check Sound settings for an input device."
        case let .engineFailed(detail):
            "Couldn't start the microphone: \(detail)"
        case let .modelUnavailable(detail):
            "Couldn't load the Parakeet model: \(detail). Switch back to Apple dictation in Settings."
        }
    }
}

/// Turns microphone audio into text.
///
/// Split out from `SpeechDictation` so the two recognizers can share one
/// microphone. Opening the input device, metering it, naming it and watching it
/// for silence is identical either way and was the fiddly part to get right;
/// only the recognition differs.
@MainActor
protocol DictationRecognizer: AnyObject {
    /// Whatever must happen before audio arrives — a permission prompt, or a
    /// model download on first use. Throws so the panel can say why nothing
    /// started rather than sitting on a dead button.
    func prepare() async throws

    /// False means the audio is leaving this Mac, which the panel states.
    var runsOnDevice: Bool { get }

    /// Begins producing text. Each call replaces the whole field, so a
    /// recognizer must report everything said since `begin`, not just the most
    /// recent phrase.
    func begin(onTranscript: @escaping (String) -> Void)

    /// Fed from the audio render thread, so this must not touch the main actor
    /// or take a lock the main actor holds.
    nonisolated func receive(_ buffer: AVAudioPCMBuffer)

    func end()
}

/// Dictation through Apple's own recognizer.
///
/// Kept as the default because it needs no download and no model on disk. Its
/// weakness is structural rather than a matter of accuracy: it finalizes a
/// segment whenever the speaker pauses and begins the next one from empty, so
/// everything below exists to stitch those segments back together.
@MainActor
final class AppleDictationRecognizer: DictationRecognizer {
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private var isRunning = false

    /// The live request, reachable from the audio thread.
    ///
    /// Held in a lock rather than as a plain property because the tap keeps
    /// feeding buffers while a pause swaps the request underneath it.
    private let inflight = RequestHolder()

    /// Text from segments the recognizer has already finalized.
    ///
    /// Reporting only the current segment erased everything said before a
    /// pause. Finalized text accumulates here and the in-progress segment is
    /// appended to it.
    private var settledTranscript = ""

    private(set) var runsOnDevice = true

    func prepare() async throws {
        guard await Self.authorizeSpeech() else { throw DictationFailure.speechDenied }

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else { throw DictationFailure.recognizerUnavailable }

        self.recognizer = recognizer
        runsOnDevice = recognizer.supportsOnDeviceRecognition
        settledTranscript = ""
    }

    func begin(onTranscript: @escaping (String) -> Void) {
        isRunning = true
        listen(onTranscript: onTranscript)
    }

    nonisolated func receive(_ buffer: AVAudioPCMBuffer) {
        inflight.append(buffer)
    }

    func end() {
        isRunning = false
        inflight.finish()
        task?.cancel()
        task = nil
        inflight.replace(with: nil)
        settledTranscript = ""
    }

    /// Starts a recognition task, and starts another whenever one finishes.
    ///
    /// A finished segment used to end the whole session, which made dictating
    /// anything with a pause in it impossible: stopping to think stopped the
    /// recording. This is push-to-talk, so only the user decides when it ends.
    private func listen(onTranscript: @escaping (String) -> Void) {
        guard let recognizer, isRunning else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = runsOnDevice
        inflight.replace(with: request)

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isRunning else { return }

                if let segment = result?.bestTranscription.formattedString, !segment.isEmpty {
                    onTranscript(self.joined(with: segment))
                }

                if let error {
                    // A segment that ends on silence reports an error rather
                    // than a result, which is ordinary here and not a failure.
                    NSLog("[Dictation] recognition ended: \(error.localizedDescription)")
                }

                guard error != nil || result?.isFinal == true else { return }

                // Commit the finished segment before the next one starts from
                // empty, or the pause would take those words with it.
                if let segment = result?.bestTranscription.formattedString, !segment.isEmpty {
                    self.settledTranscript = self.joined(with: segment)
                }

                self.task = nil
                self.listen(onTranscript: onTranscript)
            }
        }
    }

    private func joined(with segment: String) -> String {
        settledTranscript.isEmpty ? segment : settledTranscript + " " + segment
    }

    /// Holds the recognition request the audio tap is feeding.
    ///
    /// The tap runs on a render thread and the request is swapped from the main
    /// actor at every pause, so the handoff is locked.
    /// `nonisolated` because the project defaults actor isolation to the main
    /// actor, and this is reached from the audio render thread.
    private nonisolated final class RequestHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var request: SFSpeechAudioBufferRecognitionRequest?

        func replace(with request: SFSpeechAudioBufferRecognitionRequest?) {
            lock.withLock {
                self.request?.endAudio()
                self.request = request
            }
        }

        func finish() {
            lock.withLock { request?.endAudio() }
        }

        func append(_ buffer: AVAudioPCMBuffer) {
            lock.withLock { request?.append(buffer) }
        }
    }

    private static func authorizeSpeech() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized:
            return true
        case .denied, .restricted:
            return false
        case .notDetermined:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        @unknown default:
            return false
        }
    }
}

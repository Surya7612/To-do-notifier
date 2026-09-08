import AVFoundation
import Foundation
import Speech

/// Push-to-talk dictation using Apple's on-device recognizer.
///
/// Deliberately not Whisper or any hosted STT: those would ship your voice off
/// the machine for a feature whose whole point is convenience, and the plan's
/// privacy principles put local-first ahead of accuracy here. `Speech` can run
/// fully on-device, so nothing leaves the Mac.
@MainActor
final class SpeechDictation {
    enum Failure: LocalizedError {
        case micDenied
        case speechDenied
        case recognizerUnavailable
        case noInputDevice
        case engineFailed(String)

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
            }
        }
    }

    /// Rebuilt per session on purpose. An engine created before the microphone
    /// permission existed caches an input node with a zero-channel format and
    /// never recovers, which silently produces no audio at all.
    private var engine: AVAudioEngine?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

    /// The live request, reachable from the audio thread.
    ///
    /// Held in a lock rather than as a plain property because the tap keeps
    /// feeding buffers while a pause swaps the request underneath it.
    private let inflight = RequestHolder()

    /// Text from segments the recognizer has already finalized.
    ///
    /// The recognizer ends a segment at a pause and the next one starts its
    /// transcription over from empty, so reporting only the current segment
    /// erased everything said before the pause. Finalized text accumulates here
    /// and the in-progress segment is appended to it.
    private var settledTranscript = ""

    private(set) var isListening = false
    /// False means Apple's servers are transcribing; the UI says so.
    private(set) var isOnDevice = true

    /// Named in the UI because the system default input is often not the one the
    /// user assumes — AirPods sitting in their case are still the default input,
    /// and they record perfect silence without producing any error.
    private(set) var inputDeviceName = ""

    private let level = LevelMeter()
    private var silenceWatchdog: Task<Void, Never>?

    /// Speech occupies a narrow band of the available amplitude range, so the
    /// raw peak barely moves the needle. Boosted and clamped, it reads as voice.
    var currentLevel: CGFloat {
        guard isListening else { return 0 }
        return min(1, CGFloat(level.drainRecentLevel()) * 6)
    }

    func start(onTranscript: @escaping (String) -> Void,
               onEnd: @escaping () -> Void,
               onSilence: @escaping (String) -> Void) async throws {
        guard !isListening else { return }

        guard await Self.authorizeSpeech() else { throw Failure.speechDenied }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw Failure.micDenied }

        let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
            ?? SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else { throw Failure.recognizerUnavailable }
        self.recognizer = recognizer

        isOnDevice = recognizer.supportsOnDeviceRecognition
        settledTranscript = ""

        let engine = AVAudioEngine()
        self.engine = engine

        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)
        guard format.channelCount > 0, format.sampleRate > 0 else {
            NSLog("[Dictation] unusable input format: \(format)")
            cleanUp()
            throw Failure.noInputDevice
        }

        inputDeviceName = AVCaptureDevice.default(for: .audio)?.localizedName ?? "unknown input"
        level.reset()

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [level, inflight] buffer, _ in
            inflight.append(buffer)
            level.record(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            NSLog("[Dictation] engine start failed: \(error.localizedDescription)")
            cleanUp()
            throw Failure.engineFailed(error.localizedDescription)
        }

        isListening = true

        let device = inputDeviceName
        silenceWatchdog = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled, let self, self.isListening, self.level.isSilent else { return }
            NSLog("[Dictation] no audio from \(device) after 3s")
            onSilence(device)
        }

        listen(onTranscript: onTranscript, onEnd: onEnd)
    }

    /// Starts a recognition task, and starts another whenever one finishes.
    ///
    /// A finished segment used to end the whole session, which made dictating
    /// anything with a pause in it impossible: stopping to think ended the
    /// recording. This is push-to-talk, so only the user decides when it ends.
    private func listen(onTranscript: @escaping (String) -> Void,
                        onEnd: @escaping () -> Void) {
        guard let recognizer, isListening || engine != nil else { return }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = isOnDevice
        inflight.replace(with: request)

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self, self.isListening else { return }

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
                self.listen(onTranscript: onTranscript, onEnd: onEnd)
            }
        }
    }

    private func joined(with segment: String) -> String {
        settledTranscript.isEmpty ? segment : settledTranscript + " " + segment
    }

    func stop() {
        guard isListening else { return }
        // Cleared first so the recognition callback, which may already be in
        // flight, does not start another segment on the way out.
        isListening = false
        inflight.finish()
        task?.cancel()
        cleanUp()
    }

    private func cleanUp() {
        silenceWatchdog?.cancel()
        silenceWatchdog = nil
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        engine = nil
        inflight.replace(with: nil)
        task = nil
        settledTranscript = ""
    }

    /// Holds the recognition request the audio tap is feeding.
    ///
    /// The tap runs on a render thread and the request is swapped from the main
    /// actor at every pause, so the handoff is locked.
    private final class RequestHolder: @unchecked Sendable {
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

    /// Tracks whether any non-silent audio arrived. Written from the audio
    /// render thread and read from the main actor, so access is locked.
    private final class LevelMeter: @unchecked Sendable {
        private let lock = NSLock()
        /// Loudest sample of the whole session, for the silence watchdog.
        private var sessionPeak: Float = 0
        /// Loudest sample since the UI last looked, for the waveform.
        private var unreadPeak: Float = 0

        var isSilent: Bool {
            lock.withLock { sessionPeak < 0.0015 }
        }

        func reset() {
            lock.withLock {
                sessionPeak = 0
                unreadPeak = 0
            }
        }

        /// Consumes the peak so the meter falls back to zero when the user stops
        /// speaking instead of holding the loudest value forever.
        func drainRecentLevel() -> Float {
            lock.withLock {
                let value = unreadPeak
                unreadPeak = 0
                return value
            }
        }

        func record(_ buffer: AVAudioPCMBuffer) {
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            var frameMax: Float = 0
            for channel in 0..<Int(buffer.format.channelCount) {
                let samples = channels[channel]
                for frame in 0..<Int(buffer.frameLength) {
                    frameMax = max(frameMax, abs(samples[frame]))
                }
            }
            lock.withLock {
                sessionPeak = max(sessionPeak, frameMax)
                unreadPeak = max(unreadPeak, frameMax)
            }
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

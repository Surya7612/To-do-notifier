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
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var recognizer: SFSpeechRecognizer?

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

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        isOnDevice = recognizer.supportsOnDeviceRecognition
        request.requiresOnDeviceRecognition = isOnDevice
        self.request = request

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

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [level] buffer, _ in
            request.append(buffer)
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

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            if let text = result?.bestTranscription.formattedString, !text.isEmpty {
                Task { @MainActor in onTranscript(text) }
            }
            if let error {
                NSLog("[Dictation] recognition error: \(error.localizedDescription)")
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in
                    self?.stop()
                    onEnd()
                }
            }
        }
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        request?.endAudio()
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
        request = nil
        task = nil
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

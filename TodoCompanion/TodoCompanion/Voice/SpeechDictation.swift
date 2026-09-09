import AVFoundation
import Foundation

/// Push-to-talk dictation.
///
/// Owns the microphone — opening it, metering it, naming it and watching it for
/// silence — and hands the audio to whichever `DictationRecognizer` the user has
/// chosen. That split exists because the microphone half was the fiddly part and
/// is identical either way, while the recognizers differ in everything else.
///
/// Both recognizers run on this Mac. Nothing here may be swapped for a hosted
/// transcription service: shipping the user's voice off the machine for a
/// convenience feature is the thing the privacy rules exist to prevent.
@MainActor
final class SpeechDictation {
    typealias Failure = DictationFailure

    /// Rebuilt per session on purpose. An engine created before the microphone
    /// permission existed caches an input node with a zero-channel format and
    /// never recovers, which silently produces no audio at all.
    private var engine: AVAudioEngine?

    /// Kept between sessions, and rebuilt only when the chosen engine changes.
    ///
    /// Not an optimization. Parakeet's models take tens of seconds to load onto
    /// the Neural Engine, so building a recognizer per session paid that on
    /// every single press of the dictation key rather than once, and the
    /// `modelsLoaded` guard inside it never survived to be read.
    private var recognizer: (any DictationRecognizer)?
    private var recognizerEngine: AppSettings.DictationEngine?

    /// True when the next `start` has a model to load, which takes tens of
    /// seconds rather than the moment a microphone takes. The panel says so,
    /// because an unexplained wait on a key press reads as a hang.
    var willLoadModel: Bool {
        let engine = AppSettings.dictationEngine
        guard engine != .apple else { return false }
        guard engine == recognizerEngine, let recognizer else { return true }
        return !recognizer.isPrepared
    }

    private(set) var isListening = false

    /// False means something other than this Mac is transcribing; the UI says
    /// so. Only Apple's recognizer can report false, and only when its
    /// on-device model is missing for the language.
    private(set) var isOnDevice = true

    /// Named in the UI because the system default input is often not the one the
    /// user assumes — AirPods sitting in their case are still the default input,
    /// and they record perfect silence without producing any error.
    private(set) var inputDeviceName = ""

    private let level = LevelMeter()
    /// Delivers microphone buffers to the live recognizer without capturing a
    /// MainActor existential in the tap closure — see `RecognizerTap`.
    private let tap = RecognizerTap()
    private var silenceWatchdog: Task<Void, Never>?

    /// Speech occupies a narrow band of the available amplitude range, so the
    /// raw peak barely moves the needle. Boosted and clamped, it reads as voice.
    var currentLevel: CGFloat {
        guard isListening else { return 0 }
        return min(1, CGFloat(level.drainRecentLevel()) * 6)
    }

    /// - Parameter expecting: Distinctive words from the current screen, which
    ///   a recognizer able to take them biases towards.
    func start(expecting: [String] = [],
               onTranscript: @escaping (String) -> Void,
               onSilence: @escaping (String) -> Void) async throws {
        guard !isListening else { return }

        let chosenEngine = AppSettings.dictationEngine
        if chosenEngine != recognizerEngine || recognizer == nil {
            recognizer = chosenEngine.makeRecognizer()
            recognizerEngine = chosenEngine
        }
        guard let recognizer else { throw Failure.recognizerUnavailable }

        // Prepared before the microphone opens, because this is where a
        // permission prompt or a first-run model download happens and neither
        // should run with the input device held open.
        try await recognizer.prepare()
        isOnDevice = recognizer.runsOnDevice

        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw Failure.micDenied }

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

        // Bound through a Sendable box rather than capturing `recognizer` in the
        // tap. Under Swift 6 the protocol existential is MainActor-isolated, so
        // a tap that closed over it became MainActor too — and the first buffer
        // arriving on the audio render thread trapped in
        // `_swift_task_checkIsolatedSwift`. That is the crash the talk hotkey
        // hit: the shortcut worked, the microphone opened, and then the process
        // died on the first sample.
        tap.bind(recognizer)

        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [level, tap] buffer, _ in
            tap.receive(buffer)
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

        recognizer.begin(expecting: expecting, onTranscript: onTranscript)
    }

    func stop() {
        guard isListening else { return }
        // Cleared first so a recognition callback already in flight does not
        // start another segment on the way out.
        isListening = false
        recognizer?.end()
        cleanUp()
    }

    private func cleanUp() {
        silenceWatchdog?.cancel()
        silenceWatchdog = nil
        tap.unbind()
        if let engine {
            engine.inputNode.removeTap(onBus: 0)
            if engine.isRunning { engine.stop() }
        }
        engine = nil
        // The recognizer deliberately survives, holding its loaded model. Only
        // a change of engine replaces it.
    }

    /// Forwards audio-tap buffers to the live recognizer without hopping actors.
    ///
    /// Written on the main actor when listening starts, cleared when it stops,
    /// and called from the render thread. `@unchecked Sendable` for the same
    /// reason `LevelMeter` is: the lock is the synchronisation, and the values
    /// it holds are themselves safe to call from any thread (`receive` on both
    /// recognizers is `nonisolated` and only touches lock-guarded state).
    private nonisolated final class RecognizerTap: @unchecked Sendable {
        private let lock = NSLock()
        private var destination: (@Sendable (AVAudioPCMBuffer) -> Void)?

        @MainActor
        func bind(_ recognizer: any DictationRecognizer) {
            // The `@Sendable` receiver only touches lock-guarded state inside
            // the backend — never the MainActor existential itself.
            let destination = recognizer.audioReceiver
            lock.withLock { self.destination = destination }
        }

        func unbind() {
            lock.withLock { destination = nil }
        }

        func receive(_ buffer: AVAudioPCMBuffer) {
            lock.withLock { destination }?(buffer)
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
}

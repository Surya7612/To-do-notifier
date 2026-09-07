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
        case unavailable

        var errorDescription: String? {
            switch self {
            case .micDenied:
                "Microphone access is off. Enable it in System Settings → Privacy & Security → Microphone."
            case .speechDenied:
                "Speech recognition is off. Enable it in System Settings → Privacy & Security → Speech Recognition."
            case .unavailable:
                "Dictation isn't available right now."
            }
        }
    }

    private let engine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?

    private(set) var isListening = false
    /// False means Apple's servers are doing the transcription; the UI says so.
    private(set) var isOnDevice = true

    func start(onTranscript: @escaping (String) -> Void) async throws {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else { throw Failure.unavailable }

        guard await Self.authorizeSpeech() else { throw Failure.speechDenied }
        guard await AVCaptureDevice.requestAccess(for: .audio) else { throw Failure.micDenied }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
            isOnDevice = true
        } else {
            isOnDevice = false
        }
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0 else { throw Failure.unavailable }

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw Failure.unavailable
        }

        isListening = true
        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            if let text = result?.bestTranscription.formattedString {
                Task { @MainActor in onTranscript(text) }
            }
            if error != nil || result?.isFinal == true {
                Task { @MainActor in self.stop() }
            }
        }
    }

    func stop() {
        guard isListening else { return }
        isListening = false

        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning { engine.stop() }

        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
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

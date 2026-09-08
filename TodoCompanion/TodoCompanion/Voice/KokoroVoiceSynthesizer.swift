import AVFoundation
import FluidAudio
import Foundation

/// Kokoro-82M, running on the Neural Engine.
///
/// Reached through FluidAudio, which already supplies the dictation recognizer,
/// so this voice costs no new dependency. The two Swift ports of Kokoro that
/// look like the obvious choice are both unusable here: their manifests declare
/// local path dependencies, which SPM rejects in a remote package, and the
/// grapheme-to-phoneme engine they rely on pulls in MLX and with it a Metal
/// toolchain that Xcode no longer ships by default. FluidAudio runs the same
/// model with its own CoreML phonemizer and none of that.
///
/// Synthesis is not instant, so it is deliberately fed a clause at a time by
/// `SpeechPlayback` — one sentence is generated while the previous one plays.
@MainActor
final class KokoroVoiceSynthesizer: VoiceSynthesizer {
    private let manager = KokoroAneManager(variant: .english)

    /// Kokoro emits 24 kHz mono fp32. The engine resamples to the output
    /// device, which is why the format is stated at connection time.
    private static let sampleRate = 24_000.0

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var engineIsRunning = false

    private var modelsLoaded = false
    var isPrepared: Bool { modelsLoaded }

    private(set) var isSpeaking = false
    var onFinishedSpeaking: (@MainActor () -> Void)?

    /// Clauses waiting to be synthesized, and the worker draining them.
    ///
    /// Serial on purpose: the model is one piece of hardware and the sentences
    /// have to come out in the order they were written.
    private var pending: [String] = []
    private var worker: Task<Void, Never>?

    /// Buffers handed to the player that have not finished playing.
    private var unplayedBuffers = 0

    /// macOS 26.4 and 26.5 carry an Apple BNNS bug that intermittently crashes
    /// Kokoro synthesis with `EXC_BAD_ACCESS` inside libBNNS, whatever the
    /// compute units are set to; 26.6 fixes it. FluidAudio only logs a warning.
    /// An intermittent crash of the whole app is a worse outcome than a plainer
    /// voice, so this refuses and says so instead.
    static var isSupportedBySystem: Bool {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard version.majorVersion == 26 else { return true }
        return version.minorVersion < 4 || version.minorVersion > 5
    }

    func prepare() async throws {
        guard Self.isSupportedBySystem else {
            let version = ProcessInfo.processInfo.operatingSystemVersionString
            throw VoiceFailure.unsupportedSystemVersion(version)
        }
        guard !modelsLoaded else { return }

        do {
            try await manager.initialize()
        } catch {
            throw VoiceFailure.modelUnavailable(error.localizedDescription)
        }

        try startEngineIfNeeded()
        modelsLoaded = true
    }

    func enqueue(_ text: String) {
        pending.append(text)
        isSpeaking = true
        startWorkerIfIdle()
    }

    func stop() {
        worker?.cancel()
        worker = nil
        pending = []
        unplayedBuffers = 0
        isSpeaking = false

        guard engineIsRunning else { return }
        // Drops everything scheduled. `play()` again rather than leaving the
        // node stopped, or the next answer is queued into a node that never
        // renders it.
        player.stop()
        player.play()
    }

    private func startEngineIfNeeded() throws {
        guard !engineIsRunning else { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate,
                                         channels: 1) else {
            throw VoiceFailure.playbackFailed("unsupported output format")
        }

        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            throw VoiceFailure.playbackFailed(error.localizedDescription)
        }
        player.play()
        engineIsRunning = true
    }

    private func startWorkerIfIdle() {
        guard worker == nil else { return }

        worker = Task { [weak self] in
            while let self, !Task.isCancelled, !self.pending.isEmpty {
                let next = self.pending.removeFirst()
                await self.speak(next)
            }
            self?.worker = nil
            self?.settleIfDrained()
        }
    }

    private func speak(_ text: String) async {
        do {
            // The bundle's own default voice, rather than a picker. Voice packs
            // are fetched individually and nothing here can see which ones the
            // bundle actually carries, so a list would be offering choices that
            // may not resolve — and a voice that fails drops the clause.
            let result = try await manager.synthesizeDetailed(text: text)
            guard !Task.isCancelled else { return }
            try schedule(result.samples, sampleRate: Double(result.sampleRate))
        } catch is CancellationError {
            return
        } catch {
            // A clause that fails to synthesize is dropped rather than turned
            // into a visible error: the answer is already on screen, and the
            // voice is an addition to it.
            NSLog("[Voice] Kokoro clause failed: \(error.localizedDescription)")
        }
    }

    /// Below this a sample counts as silence rather than sound.
    ///
    /// Kokoro's output does not sit at exactly zero between words, so a test
    /// against zero would trim nothing at all.
    private static let silenceFloor: Float = 0.005

    /// The gap left at the end of each piece, which is the pause between one
    /// sentence and the next.
    ///
    /// Roughly what a speaker leaves at a full stop. Trimming to nothing runs
    /// sentences together, which is a different kind of wrong from the gaps
    /// this replaces.
    private static let tailSeconds = 0.18

    /// Strips the padding Kokoro puts at both ends of every synthesis.
    ///
    /// Harmless when a whole passage is synthesized in one go, and the reason
    /// clause-at-a-time delivery sounded mechanical: the model is handed one
    /// sentence at a time so playback can start early, which meant its lead-in
    /// and lead-out silence landed at *every* sentence boundary and stacked with
    /// the pause the punctuation already implies. Both ends are cut and a fixed
    /// tail put back, so the gap between sentences is one this app chose rather
    /// than one that accumulated.
    static func trimmedWithTail(_ samples: [Float], sampleRate: Double) -> [Float] {
        guard let first = samples.firstIndex(where: { abs($0) > silenceFloor }),
              let last = samples.lastIndex(where: { abs($0) > silenceFloor })
        else { return [] }

        // Appended rather than taken from what the model produced, so the gap
        // is the same at every join instead of depending on how much padding
        // this particular synthesis happened to leave.
        var trimmed = Array(samples[first...last])
        trimmed.append(contentsOf: repeatElement(0, count: Int(tailSeconds * sampleRate)))
        return trimmed
    }

    private func schedule(_ rawSamples: [Float], sampleRate: Double) throws {
        let samples = Self.trimmedWithTail(rawSamples, sampleRate: sampleRate)
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let destination = buffer.floatChannelData?[0]
        else { return }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            destination.update(from: source.baseAddress!, count: samples.count)
        }

        unplayedBuffers += 1
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.unplayedBuffers = max(0, self.unplayedBuffers - 1)
                self.settleIfDrained()
            }
        }
    }

    /// Silence is only real once nothing is queued *and* nothing is still
    /// playing, since the worker finishes generating well before the audio ends.
    private func settleIfDrained() {
        guard worker == nil, pending.isEmpty, unplayedBuffers == 0 else { return }
        isSpeaking = false
        onFinishedSpeaking?()
    }
}

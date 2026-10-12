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
    var onStartedSpeaking: (@MainActor (String) -> Void)?
    var onWordStarted: (@MainActor (String, Int) -> Void)?

    /// When each word of each scheduled clause is heard, index for index with
    /// `scheduledClauses`, and the timer firing the cues of the one playing.
    private var scheduledCues: [[WordTiming.Cue]] = []
    private var cueTimer: Task<Void, Never>?

    /// Clauses waiting to be synthesized, and the worker draining them.
    ///
    /// Serial on purpose: the model is one piece of hardware and the sentences
    /// have to come out in the order they were written.
    private var pending: [String] = []
    private var worker: Task<Void, Never>?

    /// The words behind each buffer handed to the player that has not finished
    /// playing, oldest first — so the head of this is what is being heard.
    ///
    /// Doubles as the count of unplayed buffers. Kept as the text rather than a
    /// number because a clause is synthesized while the previous one is still
    /// playing, so "which clause was most recently scheduled" runs a sentence
    /// ahead of the sound and is the wrong thing to report.
    private var scheduledClauses: [String] = []

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
        scheduledClauses = []
        scheduledCues = []
        cueTimer?.cancel()
        cueTimer = nil
        isSpeaking = false

        guard engineIsRunning else { return }
        // Drops everything scheduled. `play()` again rather than leaving the
        // node stopped, or the next answer is queued into a node that never
        // renders it.
        player.stop()
        player.play()
    }

    private var playerAttached = false
    private var configurationObserver: NSObjectProtocol?

    /// Checks the engine itself rather than trusting `engineIsRunning`, because
    /// macOS stops an `AVAudioEngine` on its own whenever the audio hardware
    /// changes — headphones plugged in, AirPods switching to their headset
    /// profile because the microphone opened. A stopped engine accepts
    /// `scheduleBuffer` without complaint, never plays it and never calls its
    /// completion, so the voice went silent with the stop button stuck lit.
    private func startEngineIfNeeded() throws {
        if engineIsRunning, engine.isRunning { return }
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate,
                                         channels: 1) else {
            throw VoiceFailure.playbackFailed("unsupported output format")
        }

        if !playerAttached {
            engine.attach(player)
            playerAttached = true
            configurationObserver = NotificationCenter.default.addObserver(
                forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in self?.recoverFromConfigurationChange() }
            }
        }
        engine.connect(player, to: engine.mainMixerNode, format: format)

        do {
            try engine.start()
        } catch {
            engineIsRunning = false
            throw VoiceFailure.playbackFailed(error.localizedDescription)
        }
        player.play()
        engineIsRunning = true
    }

    /// The change has already dropped whatever was scheduled, so those clauses
    /// will never report finishing; forgetting them is what lets `isSpeaking`
    /// clear instead of waiting forever. Synthesis still queued plays on the
    /// restarted engine.
    private func recoverFromConfigurationChange() {
        engineIsRunning = false
        scheduledClauses = []
        scheduledCues = []
        cueTimer?.cancel()
        cueTimer = nil
        do {
            try startEngineIfNeeded()
        } catch {
            NSLog("[Voice] Kokoro could not restart audio: \(error.localizedDescription)")
        }
        settleIfDrained()
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
            // Phonemized here rather than inside the synthesis call so the
            // phoneme string is in hand alongside the durations it produced,
            // which is what places each word in time.
            let spoken = SpokenForm.of(text)
            let phonemes = try await manager.phonemes(for: spoken.text)
            let result = try await manager.synthesizeFromPhonemesDetailed(phonemes)
            guard !Task.isCancelled else { return }
            let sampleRate = Double(result.sampleRate)
            let cues = WordTiming.cues(text: spoken.text,
                                       phonemes: phonemes,
                                       durations: result.predictedDurations,
                                       totalSeconds: result.durationSeconds)
                .map { WordTiming.Cue(characterOffset: spoken.writtenOffset($0.characterOffset), seconds: $0.seconds) }
            try schedule(result.samples, sampleRate: sampleRate, saying: text, cues: cues)
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
        guard let first = leadingSilence(in: samples),
              let last = samples.lastIndex(where: { abs($0) > silenceFloor })
        else { return [] }

        // Appended rather than taken from what the model produced, so the gap
        // is the same at every join instead of depending on how much padding
        // this particular synthesis happened to leave.
        var trimmed = Array(samples[first...last])
        trimmed.append(contentsOf: repeatElement(0, count: Int(tailSeconds * sampleRate)))
        return trimmed
    }

    /// Samples cut from the front by `trimmedWithTail`, which every word cue
    /// has to be moved earlier by.
    static func leadingSilence(in samples: [Float]) -> Int? {
        samples.firstIndex(where: { abs($0) > silenceFloor })
    }

    private func schedule(_ rawSamples: [Float],
                          sampleRate: Double,
                          saying text: String,
                          cues rawCues: [WordTiming.Cue]) throws {
        let samples = Self.trimmedWithTail(rawSamples, sampleRate: sampleRate)
        let trimmedSeconds = Double(Self.leadingSilence(in: rawSamples) ?? 0) / sampleRate
        let cues = rawCues.map {
            WordTiming.Cue(characterOffset: $0.characterOffset, seconds: max(0, $0.seconds - trimmedSeconds))
        }
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let destination = buffer.floatChannelData?[0]
        else { return }
        try startEngineIfNeeded()

        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { source in
            destination.update(from: source.baseAddress!, count: samples.count)
        }

        // Nothing ahead of it in the queue means the player starts on it as
        // soon as it is scheduled.
        let startsImmediately = scheduledClauses.isEmpty
        scheduledClauses.append(text)
        scheduledCues.append(cues)

        // The audio thread calls this, so the hop to the main actor is the
        // point. `self` is captured by the `Task` rather than read out of the
        // enclosing closure: a weak capture is mutable, and reading one across
        // a concurrency boundary is an error under the Swift 6 language mode.
        player.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if !self.scheduledClauses.isEmpty { self.scheduledClauses.removeFirst() }
                if !self.scheduledCues.isEmpty { self.scheduledCues.removeFirst() }
                // One finishing is what tells us the next has begun; the player
                // reports completion only.
                if let nowPlaying = self.scheduledClauses.first {
                    self.startedHearing(nowPlaying, cues: self.scheduledCues.first ?? [])
                } else {
                    self.cueTimer?.cancel()
                    self.cueTimer = nil
                }
                self.settleIfDrained()
            }
        }

        if startsImmediately { startedHearing(text, cues: cues) }
    }

    /// Reports the clause, then each of its words at the moment it is heard.
    ///
    /// Timed from here rather than read off the audio clock: the player only
    /// reports a buffer *finishing*, and the start of the next is the closest
    /// thing to "now playing" it offers.
    private func startedHearing(_ clause: String, cues: [WordTiming.Cue]) {
        onStartedSpeaking?(clause)
        cueTimer?.cancel()
        guard !cues.isEmpty else {
            cueTimer = nil
            return
        }
        let began = ContinuousClock.now
        cueTimer = Task { [weak self] in
            for cue in cues {
                try? await Task.sleep(until: began + .milliseconds(Int(cue.seconds * 1_000)),
                                      clock: .continuous)
                guard !Task.isCancelled, let self else { return }
                self.onWordStarted?(clause, cue.characterOffset)
            }
        }
    }

    /// Silence is only real once nothing is queued *and* nothing is still
    /// playing, since the worker finishes generating well before the audio ends.
    private func settleIfDrained() {
        guard worker == nil, pending.isEmpty, scheduledClauses.isEmpty else { return }
        isSpeaking = false
        onFinishedSpeaking?()
    }
}

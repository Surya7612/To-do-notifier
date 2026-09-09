import AVFoundation
import FluidAudio
import Foundation

/// Dictation through Parakeet, running on the Neural Engine.
///
/// Chosen over Whisper for the same reason Apple's recognizer was: it is a
/// CoreML model executing on this Mac, so the privacy rule holds. What it buys
/// over Apple's is that its transcript is *cumulative* — the model keeps its own
/// accumulated tokens across pauses, so the pause-erases-words problem is absent
/// by construction rather than stitched back together afterwards.
///
/// The cost is a model download of a little over a hundred megabytes the first
/// time it runs, which is why Apple's recognizer stays the default.
@MainActor
final class ParakeetDictationRecognizer: DictationRecognizer {
    private let manager = StreamingEouAsrManager()
    /// `nonisolated` so the microphone tap can capture it in a `@Sendable`
    /// closure without dragging this MainActor-isolated recognizer along.
    nonisolated private let queue = SampleQueue()
    private var drainTask: Task<Void, Never>?
    private var modelsLoaded = false

    /// The whole point of the model being on disk.
    let runsOnDevice = true

    var isPrepared: Bool { modelsLoaded }

    /// How often buffered audio is handed to the model.
    ///
    /// The recognizer is an actor and the audio render thread cannot await, so
    /// samples are queued and pushed on an interval instead. Kept under the
    /// model's own 160ms chunk so a spoken word is not waiting on our poll on
    /// top of inference — 300ms here made Parakeet feel a beat behind speech.
    private static let pushInterval = Duration.milliseconds(80)

    func prepare() async throws {
        guard !modelsLoaded else { return }

        do {
            try await manager.loadModels()
            modelsLoaded = true
        } catch {
            throw DictationFailure.modelUnavailable(error.localizedDescription)
        }
    }

    /// - Parameter expecting: Ignored. The streaming manager takes no
    ///   vocabulary hints, so there is nowhere to put them. Silently accepting
    ///   them keeps the caller from having to know which backend it has.
    func begin(expecting: [String], onTranscript: @escaping (String) -> Void) {
        queue.reset()

        // Boxed so the actor's Sendable partial callback can reach the
        // MainActor-only UI update without capturing a non-Sendable closure.
        let sink = ParakeetTranscriptSink(onTranscript)

        drainTask = Task { [manager, queue] in
            // Push updates as the model decodes rather than only when we poll.
            await manager.setPartialTranscriptCallback { text in
                guard !text.isEmpty else { return }
                sink.publish(text)
            }

            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pushInterval)
                guard !Task.isCancelled else { return }

                let pending = queue.drain()
                guard !pending.isEmpty else { continue }

                do {
                    for chunk in pending {
                        guard let buffer = chunk.makeBuffer() else { continue }
                        try await manager.appendAudio(buffer)
                    }
                    try await manager.processBufferedAudio()

                    // Callback may already have fired; this catches a decode
                    // that produced text without invoking it.
                    let text = await manager.getPartialTranscript()
                    if !text.isEmpty { sink.publish(text) }
                } catch {
                    NSLog("[Dictation] Parakeet chunk failed: \(error.localizedDescription)")
                }
            }
        }
    }

    nonisolated func receive(_ buffer: AVAudioPCMBuffer) {
        Self.enqueue(buffer, onto: queue)
    }

    nonisolated var audioReceiver: @Sendable (AVAudioPCMBuffer) -> Void {
        { [queue] buffer in Self.enqueue(buffer, onto: queue) }
    }

    /// Samples are copied rather than the buffer retained. A tap's buffer is
    /// only valid for the duration of the callback, and this recognizer looks at
    /// the audio a fraction of a second later, by which time the engine has
    /// reused the storage. Apple's path escapes this because `append` copies
    /// synchronously.
    private nonisolated static func enqueue(_ buffer: AVAudioPCMBuffer, onto queue: SampleQueue) {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return }

        let samples = Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
        queue.append(SampleChunk(samples: samples, sampleRate: buffer.format.sampleRate))
    }

    func end() {
        drainTask?.cancel()
        drainTask = nil
        queue.reset()

        // Discards the accumulated tokens, so the next session starts empty
        // rather than continuing the last one's sentence.
        Task { [manager] in
            await manager.setPartialTranscriptCallback { _ in }
            await manager.reset()
        }
    }

    /// One tap callback's worth of mono audio.
    private struct SampleChunk: Sendable {
        let samples: [Float]
        let sampleRate: Double

        /// `sending`, because the buffer is handed to the recognizer actor and
        /// `AVAudioPCMBuffer` is not `Sendable`. It is allocated here from
        /// values that are, and nothing keeps a reference to it, so the region
        /// really is disconnected — the compiler just cannot see that across a
        /// return without being told.
        func makeBuffer() -> sending AVAudioPCMBuffer? {
            guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1),
                  let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(samples.count)),
                  let destination = buffer.floatChannelData?[0]
            else { return nil }

            buffer.frameLength = AVAudioFrameCount(samples.count)
            samples.withUnsafeBufferPointer { source in
                destination.update(from: source.baseAddress!, count: samples.count)
            }
            return buffer
        }
    }

    /// Audio waiting to be pushed to the model.
    ///
    /// Written from the render thread and read from the main actor, so access is
    /// locked. Bounded because a model that stalls must not turn into unbounded
    /// memory growth on a machine this feature is meant to be light on; dropping
    /// the oldest audio costs a few words, and running the Mac out of memory
    /// costs the session.
    private nonisolated final class SampleQueue: @unchecked Sendable {
        private let lock = NSLock()
        private var chunks: [SampleChunk] = []

        /// Roughly thirty seconds at the tap's buffer size.
        private static let limit = 1500

        func append(_ chunk: SampleChunk) {
            lock.withLock {
                chunks.append(chunk)
                if chunks.count > Self.limit { chunks.removeFirst(chunks.count - Self.limit) }
            }
        }

        func drain() -> [SampleChunk] {
            lock.withLock {
                let pending = chunks
                chunks = []
                return pending
            }
        }

        func reset() {
            lock.withLock { chunks = [] }
        }
    }
}

/// Carries a transcript callback across the FluidAudio actor boundary.
///
/// File-scoped so it does not inherit MainActor from
/// `ParakeetDictationRecognizer` under default actor isolation.
nonisolated final class ParakeetTranscriptSink: @unchecked Sendable {
    private let deliver: (String) -> Void

    init(_ deliver: @escaping (String) -> Void) {
        self.deliver = deliver
    }

    func publish(_ text: String) {
        DispatchQueue.main.async { self.deliver(text) }
    }
}

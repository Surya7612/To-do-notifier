import AppKit
import Observation
import SwiftData

@MainActor
@Observable
final class CompanionViewModel {
    enum Phase: Equatable {
        case idle
        case reading
        case thinking
        case answering
        case saved(String)
        case needsPermission
        case failed(String)
    }

    /// Set by the panel controller so the cursor ring tracks capture exactly.
    var onCaptureBegan: (() -> Void)?
    var onCaptureEnded: (() -> Void)?
    var onListeningBegan: (() -> Void)?
    var onListeningEnded: (() -> Void)?

    private let dictation = SpeechDictation()

    var isListening: Bool { dictation.isListening }
    var dictationIsOnDevice: Bool { dictation.isOnDevice }

    var phase: Phase = .idle
    var question: String = ""
    var answer: String = ""
    var contextLabel: String = "Nothing captured yet"

    /// Things saved earlier that look relevant to the screen in front of the user.
    var related: [RetrievalMatch] = []

    private let modelContext: ModelContext
    private var observation: ScreenObservation?
    private var captureTask: Task<Void, Never>?
    private var answerTask: Task<Void, Never>?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    var isBusy: Bool { phase == .thinking || phase == .answering }
    var hasCapture: Bool { observation != nil }

    var statusText: String {
        if isListening {
            return dictation.isOnDevice
                ? "Listening… (on-device)"
                : "Listening… (Apple servers — on-device unavailable)"
        }
        switch phase {
        case .idle: return contextLabel
        case .reading: return "Reading your screen…"
        case .thinking: return "Thinking…"
        case .answering: return "Answering…"
        case let .saved(message): return message
        case .needsPermission: return "Screen Recording permission needed"
        case let .failed(message): return message
        }
    }

    /// Snapshots the screen behind the companion. Called as the panel appears so
    /// an answer can start the moment the user hits return.
    func captureScreen(frontmostApp: NSRunningApplication?) {
        captureTask?.cancel()
        phase = .reading
        onCaptureBegan?()

        captureTask = Task {
            defer { onCaptureEnded?() }
            do {
                var fresh = try await ScreenCapture.captureDisplayUnderCursor(frontmostApp: frontmostApp)
                let image = fresh.image
                fresh.recognizedText = await Task.detached {
                    TextRecognizer.recognize(in: image)
                }.value
                guard !Task.isCancelled else { return }
                observation = fresh
                contextLabel = fresh.contextLabel
                related = ContextRetriever.related(to: fresh, among: recentContexts())
                if phase == .reading { phase = .idle }
            } catch ScreenCaptureError.permissionDenied {
                guard !Task.isCancelled else { return }
                phase = .needsPermission
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Retries after the user grants permission, so they don't have to guess
    /// whether it took effect.
    func retryCapture(frontmostApp: NSRunningApplication?) {
        captureScreen(frontmostApp: frontmostApp)
    }

    /// Dictates into the same field used for typing, so speech and text are the
    /// same input rather than two separate flows.
    func toggleDictation() {
        if dictation.isListening {
            dictation.stop()
            onListeningEnded?()
            return
        }

        Task {
            do {
                onListeningBegan?()
                try await dictation.start { [weak self] text in
                    self?.question = text
                }
                if !dictation.isListening { onListeningEnded?() }
            } catch {
                onListeningEnded?()
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func openScreenRecordingSettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
        if let url { NSWorkspace.shared.open(url) }
    }

    func submit() {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isBusy else { return }

        answerTask?.cancel()
        answer = ""
        phase = .thinking

        let brain = makeBrain()
        let includeImage = AppSettings.sendsImage
        let snapshot = observation
        let memories = ContextRetriever.promptLines(for: related)

        answerTask = Task {
            do {
                let stream = brain.answerStream(question: prompt,
                                                observation: snapshot,
                                                memories: memories,
                                                includeImage: includeImage)
                for try await chunk in stream {
                    if Task.isCancelled { return }
                    answer += chunk
                    if phase != .answering { phase = .answering }
                }
                if !Task.isCancelled { phase = .idle }
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    /// Persists the current screen with whatever the user typed as the reason.
    /// The typed text is the record's intent; `#tags` inside it become topics.
    func saveCurrentContext() {
        guard let observation else {
            phase = .failed("Nothing captured yet.")
            return
        }

        let raw = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else {
            phase = .failed("Type why this matters, then save.")
            return
        }

        let (intent, topics) = raw.splittingHashtags()
        let record = SavedContext(
            intent: intent,
            recognizedText: observation.recognizedText,
            imageData: ImageCodec.pngData(from: observation.image),
            sourceApp: observation.appName ?? "",
            windowTitle: observation.windowTitle ?? "",
            topics: topics
        )

        modelContext.insert(record)
        do {
            try modelContext.save()
        } catch {
            phase = .failed("Couldn't save: \(error.localizedDescription)")
            return
        }

        question = ""
        phase = .saved(topics.isEmpty ? "Saved." : "Saved · \(topics.map { "#\($0)" }.joined(separator: " "))")
        addSummary(to: record)
    }

    /// Fills in the model's own description in the background so saving stays instant.
    private func addSummary(to record: SavedContext) {
        let brain = makeBrain()
        let intent = record.intent
        let screenText = record.recognizedText

        Task {
            guard let summary = try? await brain.summarize(intent: intent, screenText: screenText),
                  !summary.isEmpty
            else { return }
            record.aiSummary = summary
            try? modelContext.save()
        }
    }

    func reset() {
        captureTask?.cancel()
        answerTask?.cancel()
        if dictation.isListening {
            dictation.stop()
            onListeningEnded?()
        }
        question = ""
        answer = ""
        observation = nil
        related = []
        phase = .idle
        contextLabel = "Nothing captured yet"
    }

    private func makeBrain() -> OllamaBrain {
        OllamaBrain(endpoint: AppSettings.endpoint, model: AppSettings.model)
    }

    /// Scoring runs in memory, so cap the candidate set rather than growing
    /// the work forever as the store fills up.
    private func recentContexts() -> [SavedContext] {
        var descriptor = FetchDescriptor<SavedContext>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = 300
        return (try? modelContext.fetch(descriptor)) ?? []
    }
}

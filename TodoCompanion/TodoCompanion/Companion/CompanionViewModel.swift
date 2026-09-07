import AppKit
import Observation

@MainActor
@Observable
final class CompanionViewModel {
    enum Phase: Equatable {
        case idle
        case reading
        case thinking
        case answering
        case failed(String)
    }

    var phase: Phase = .idle
    var question: String = ""
    var answer: String = ""
    var contextLabel: String = "Nothing captured yet"

    private var observation: ScreenObservation?
    private var captureTask: Task<Void, Never>?
    private var answerTask: Task<Void, Never>?

    var isBusy: Bool { phase == .thinking || phase == .answering }

    var statusText: String {
        switch phase {
        case .idle: contextLabel
        case .reading: "Reading your screen…"
        case .thinking: "Thinking…"
        case .answering: "Answering…"
        case let .failed(message): message
        }
    }

    /// Snapshots the screen behind the companion. Called as the panel appears so
    /// an answer can start the moment the user hits return.
    func captureScreen(frontmostApp: NSRunningApplication?) {
        captureTask?.cancel()
        phase = .reading
        captureTask = Task {
            do {
                var fresh = try await ScreenCapture.captureDisplayUnderCursor(frontmostApp: frontmostApp)
                if !AppSettings.sendsImage {
                    let image = fresh.image
                    fresh.recognizedText = await Task.detached { TextRecognizer.recognize(in: image) }.value
                }
                guard !Task.isCancelled else { return }
                observation = fresh
                contextLabel = fresh.contextLabel
                if phase == .reading { phase = .idle }
            } catch {
                guard !Task.isCancelled else { return }
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func submit() {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isBusy else { return }

        answerTask?.cancel()
        answer = ""
        phase = .thinking

        let brain = OllamaBrain(endpoint: AppSettings.endpoint, model: AppSettings.model)
        let includeImage = AppSettings.sendsImage
        let snapshot = observation

        answerTask = Task {
            do {
                let stream = brain.answerStream(question: prompt,
                                                observation: snapshot,
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

    func reset() {
        captureTask?.cancel()
        answerTask?.cancel()
        question = ""
        answer = ""
        observation = nil
        phase = .idle
        contextLabel = "Nothing captured yet"
    }
}

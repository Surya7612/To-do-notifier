import Foundation

/// Anything that can answer a question about the screen.
///
/// Note what is deliberately *absent*: summarizing a saved context. That work
/// happens in the background, unprompted, on material that accumulates across
/// everything the user keeps. Leaving it off this protocol means a cloud brain
/// cannot be wired up to it by accident — the compiler enforces the rule that
/// only a question the user actually asked may leave the machine.
protocol Brain: Sendable {
    /// Shown in the panel so the user always knows who is answering.
    var label: String { get }

    /// Whether using this sends screen contents off the device.
    var leavesTheMachine: Bool { get }

    func answerStream(question: String, context: AskContext) -> AsyncThrowingStream<String, Error>
}

/// Everything a question is answered against.
///
/// Grouped rather than passed as five arguments so adding a source of context
/// does not mean editing every provider's signature.
struct AskContext: Sendable {
    var observation: ScreenObservation?
    /// Things the user saved earlier, in their own words.
    var memories: [String] = []
    /// Open tasks from the To-Do Notifier, if it has been linked.
    var tasks: [String] = []
    var includeImage = false
}

enum BrainError: LocalizedError {
    case unreachable
    case missingKey
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .unreachable:
            "Can't reach Ollama. Start it with `ollama serve`, then try again."
        case .missingKey:
            "Add an OpenAI API key in Settings, or switch back to the local model."
        case let .http(code, detail):
            "Request failed (\(code)): \(detail)"
        }
    }
}

/// The wording sent to every model, kept in one place so switching providers
/// cannot quietly change the app's behaviour.
enum Prompt {
    static let system = """
    You are a concise desktop companion. You are shown what is currently on the user's screen, \
    any notes the user saved earlier that look related, and their question. Answer directly in \
    at most four sentences. If you do not know, say that instead of guessing.

    The "Active window" line is ground truth for which application the user is in; it comes from \
    the operating system, not from looking at pixels. Never contradict it. If that application is \
    displaying something else — a screenshot, a PDF, a video, a design mockup — then the user is \
    working in the active window and merely looking at that content. Say so in those terms rather \
    than claiming the screen is the thing being displayed.

    The user's own saved notes outrank your reading of the screen — if they conflict, trust the \
    note and say so. Saved notes are background, not the question; do not bring one up unless it \
    bears on what was actually asked.
    """

    static func user(question: String, context: AskContext) -> String {
        var parts: [String] = []
        let observation = context.observation
        let includeImage = context.includeImage

        if let observation {
            parts.append("Active window: \(observation.contextLabel)")

            if observation.isCropped {
                parts.append("The user selected one region of the screen. Answer about that region.")
            }

            if includeImage {
                // The attached image is the focused display only. Running a
                // local vision model over every monitor costs far more than the
                // extra pixels are worth, so the others come through as text.
                let secondary = observation.others.filter { !$0.recognizedText.isEmpty }
                if !secondary.isEmpty {
                    parts.append(
                        "The image is your focused display. Text on your other displays:\n"
                            + secondary
                            .map { "[Display \($0.index)]\n\($0.recognizedText)" }
                            .joined(separator: "\n\n")
                    )
                }
            } else if !observation.recognizedText.isEmpty {
                parts.append("Text visible on screen:\n\(observation.recognizedText)")
            }
        }

        if !context.memories.isEmpty {
            parts.append("The user saved these earlier, in their own words:\n"
                         + context.memories.joined(separator: "\n"))
        }

        if !context.tasks.isEmpty {
            parts.append("Open tasks from the user's to-do app:\n"
                         + context.tasks.joined(separator: "\n"))
        }

        parts.append("Question: \(question)")
        return parts.joined(separator: "\n\n")
    }
}

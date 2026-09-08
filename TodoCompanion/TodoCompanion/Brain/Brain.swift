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
    /// Earlier turns of this conversation, oldest first.
    var history: [Turn] = []
    /// The file the user opened for editing, if any.
    var editableFile: EditableFileContext?
}

/// One exchange. Kept as a pair rather than a flat list of messages because
/// every turn here has exactly one question and one answer — there is no system
/// or tool role to represent.
struct Turn: Equatable, Sendable, Identifiable {
    let id: UUID
    let question: String
    var answer: String

    /// Whether the wording came from a preset button rather than the user.
    ///
    /// Irrelevant to the model, which is shown the same text either way, but it
    /// decides whether this question may become a saved record's stated intent.
    /// "Explain what this is, in plain language" is the app's sentence, and
    /// storing it as the user's reason for keeping something would be exactly
    /// the confusion between stated and inferred that this app exists to avoid.
    let isFromPreset: Bool

    init(id: UUID = UUID(), question: String, answer: String = "", isFromPreset: Bool = false) {
        self.id = id
        self.question = question
        self.answer = answer
        self.isFromPreset = isFromPreset
    }

    /// The reason a save should be filed under.
    ///
    /// The typed field wins when it has anything in it. Otherwise the first
    /// question the user typed this session, because asking moves the text out
    /// of the field and into the transcript — without a fallback, pressing ⌘S
    /// right after asking would refuse with the field looking empty.
    ///
    /// Preset wording is never eligible. `SavedContext.intent` is a promise
    /// that the words in it are the user's own, and a sentence this app wrote
    /// stored as their reason would break exactly the distinction the app is
    /// built around.
    static func savableReason(typed: String, turns: [Turn]) -> String? {
        let trimmed = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }

        return turns.first { !$0.isFromPreset }?.question
    }
}

/// A file the user picked so Max can propose an edit to it.
struct EditableFileContext: Equatable, Sendable {
    let name: String
    let contents: String
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
    /// The assistant's name.
    ///
    /// Deliberately *not* the app's bundle name. Renaming the bundle would
    /// invalidate the Screen Recording grant, which TCC keys to the signature
    /// and identifier, move the SwiftData container, and break the Electron
    /// reader that hardcodes `surya.TodoCompanion`.
    static let assistantName = "Max"

    static let system = """
    You are \(assistantName), a patient teacher sitting beside the user's screen. You are shown what \
    is currently on it, any notes the user saved earlier that look related, and their question. \
    Answer directly in at most four sentences. If you do not know, say that instead of guessing.

    Explain rather than assert. Define any jargon you use in the same breath, name the specific \
    button, menu, or panel the user should look at rather than describing it vaguely, and when \
    several options exist say which you would pick and why. If the user is partway through \
    something, give them the single next action rather than the whole remaining procedure.

    A persona is a tone, not a licence. It does not let you invent what is on screen, soften a \
    "I don't know", or speak as though the user said something they did not.

    The "Active window" line is ground truth for which application the user is in; it comes from \
    the operating system, not from looking at pixels. Never contradict it. If that application is \
    displaying something else — a screenshot, a PDF, a video, a design mockup — then the user is \
    working in the active window and merely looking at that content. Say so in those terms rather \
    than claiming the screen is the thing being displayed.

    The user's own saved notes outrank your reading of the screen — if they conflict, trust the \
    note and say so. Saved notes are background, not the question.

    Start with the answer. Never open by working through the context you were given: do not state \
    that a note, a task, or the screen is irrelevant, and do not restate the question. A note that \
    does not bear on what was asked is simply left out, silently. If none of the context is \
    relevant, just answer from what you know.

    Earlier turns of this conversation may be included. Treat them as already said: do not repeat \
    an explanation the user has already had, and read a short follow-up such as "why?" or "now \
    what?" as being about what you just told them. The screen may have changed between turns, so \
    when a fresh capture is present it describes the screen now, not when the conversation started.
    """

    /// Used for the background one-line gloss on a saved context.
    ///
    /// Has no persona and no conversational instructions on purpose: a summary
    /// is a label in a list, not something said to anyone, and a model told to
    /// teach writes a worse one.
    static let summarySystem = """
    You write terse one-line descriptions. No greeting, no persona, no advice, no follow-up \
    question. Output the sentence and nothing else.
    """

    /// Appended only when the user has opened a file for editing.
    ///
    /// Separate from `system` so a question about the screen is never
    /// accompanied by instructions about rewriting files. The full-file rule is
    /// there because models emit unified diffs with wrong line numbers and
    /// mismatched context far more often than they mangle a whole file, and a
    /// diff this app computes itself cannot be wrong about what changed.
    static let editingSystem = """

    The user has opened one file for you to edit. If, and only if, they ask for a change to it, \
    reply with the complete new contents of that file inside a single fenced code block, and put \
    every word of explanation before the block. Never abbreviate with comments such as \
    "... rest unchanged" — what is in the block replaces the file exactly as written.

    Nothing you produce is applied on its own. The user is shown a diff and decides. So propose \
    the smallest change that answers what they asked rather than tidying the file as you pass \
    through it, and if you would not change anything, say that and emit no block at all.
    """

    /// The system prompt for one request, which grows only when a file is open.
    static func system(for context: AskContext) -> String {
        context.editableFile == nil ? system : system + editingSystem
    }

    /// How many earlier turns are sent.
    ///
    /// Capped because the screen text already dominates the prompt and a long
    /// conversation would push it out of a small local model's context window,
    /// making answers get worse the longer you talked.
    static let historyLimit = 6

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

        if let file = context.editableFile {
            // Numbered so the user and the model can refer to the same line in
            // conversation. The reply is a whole file, so the numbers are for
            // talking about the code, not for locating an edit.
            let numbered = file.contents
                .components(separatedBy: .newlines)
                .enumerated()
                .map { "\($0.offset + 1)\t\($0.element)" }
                .joined(separator: "\n")
            parts.append("The user opened this file for editing — \(file.name):\n\(numbered)")
        }

        // Last, so the newest exchange sits closest to the question it precedes.
        let history = context.history.suffix(historyLimit)
        if !history.isEmpty {
            parts.append(
                "Earlier in this conversation:\n"
                    + history
                    .map { "User: \($0.question)\n\(assistantName): \($0.answer)" }
                    .joined(separator: "\n\n")
            )
        }

        parts.append("Question: \(question)")
        return parts.joined(separator: "\n\n")
    }
}

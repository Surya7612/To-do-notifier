import Foundation

/// An OpenAI model offered in Settings.
///
/// The list is fixed rather than fetched from `/v1/models`, for two reasons.
/// That endpoint only answers for a key that already works, so the picker would
/// be empty in the one state where a new user needs it most — before they have
/// pasted anything. And it returns every model the key can reach, including the
/// embedding, audio and image models this app has no way to call, so most of
/// what it listed would be wrong answers presented as choices.
nonisolated struct OpenAIModelChoice: Identifiable, Hashable, Sendable {
    /// The name sent to the API, which is also what the panel badge shows.
    let id: String
    let displayName: String

    /// Why you would pick this one. Describes the tier rather than quoting a
    /// price: these rates were cut twice in one quarter, and a stale number
    /// sitting in the UI is worse than no number.
    let detail: String

    static let all: [OpenAIModelChoice] = [
        OpenAIModelChoice(id: "gpt-5.6-terra",
                          displayName: "GPT-5.6 Terra",
                          detail: "Balanced. The best fit for questions about what is on screen."),
        OpenAIModelChoice(id: "gpt-5.6-sol",
                          displayName: "GPT-5.6 Sol",
                          detail: "Strongest reasoning, and the dearest. Worth it when Max is proposing a file edit."),
        OpenAIModelChoice(id: "gpt-5.6-luna",
                          displayName: "GPT-5.6 Luna",
                          detail: "Fastest and cheapest. Reads text back well, thin when asked what to do next."),
        OpenAIModelChoice(id: "gpt-4o-mini",
                          displayName: "GPT-4o mini (legacy)",
                          detail: "Two generations old. Listed so an existing setting appears as itself rather than as a custom name."),
    ]

    /// What the picker's selection means. `custom` is not a model — it reveals
    /// the text field, so a model released after this build is still reachable
    /// without shipping an update.
    enum Selection: Hashable, Sendable {
        case known(String)
        case custom
    }

    static func named(_ id: String?) -> OpenAIModelChoice? {
        all.first { $0.id == id }
    }

    static func selection(for model: String) -> Selection {
        named(model) == nil ? .custom : .known(model)
    }
}

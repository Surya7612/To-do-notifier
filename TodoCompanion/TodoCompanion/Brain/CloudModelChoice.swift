import Foundation

/// A Claude model offered in Settings.
///
/// Fixed list for the same reasons as `OpenAIModelChoice`: `/v1/models` needs a
/// working key and returns more than this app can call.
nonisolated struct AnthropicModelChoice: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let detail: String

    static let all: [AnthropicModelChoice] = [
        AnthropicModelChoice(id: "claude-sonnet-4-5",
                             displayName: "Claude Sonnet 4.5",
                             detail: "Balanced. The best fit for questions about what is on screen."),
        AnthropicModelChoice(id: "claude-opus-4-5",
                             displayName: "Claude Opus 4.5",
                             detail: "Strongest reasoning. Worth it when Max is proposing a file edit."),
        AnthropicModelChoice(id: "claude-haiku-4-5",
                             displayName: "Claude Haiku 4.5",
                             detail: "Fastest. Reads text back well; thinner on what to do next."),
    ]

    enum Selection: Hashable, Sendable {
        case known(String)
        case custom
    }

    static func named(_ id: String?) -> AnthropicModelChoice? {
        all.first { $0.id == id }
    }

    static func selection(for model: String) -> Selection {
        named(model) == nil ? .custom : .known(model)
    }
}

/// A Gemini model offered in Settings.
nonisolated struct GeminiModelChoice: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let detail: String

    static let all: [GeminiModelChoice] = [
        GeminiModelChoice(id: "gemini-2.5-flash",
                          displayName: "Gemini 2.5 Flash",
                          detail: "Fast and capable. The best default for questions about the screen."),
        GeminiModelChoice(id: "gemini-2.5-pro",
                          displayName: "Gemini 2.5 Pro",
                          detail: "Stronger reasoning. Worth it for harder follow-ups and file edits."),
        GeminiModelChoice(id: "gemini-2.0-flash",
                          displayName: "Gemini 2.0 Flash (legacy)",
                          detail: "Listed so an existing setting appears as itself rather than as a custom name."),
    ]

    enum Selection: Hashable, Sendable {
        case known(String)
        case custom
    }

    static func named(_ id: String?) -> GeminiModelChoice? {
        all.first { $0.id == id }
    }

    static func selection(for model: String) -> Selection {
        named(model) == nil ? .custom : .known(model)
    }
}

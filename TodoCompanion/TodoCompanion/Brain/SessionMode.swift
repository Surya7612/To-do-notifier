import Foundation

/// How Max should shape answers for this session.
///
/// One personality, four stances. The mode narrows the system prompt the way
/// `ScreenKind` does — it never suppresses an answer, and it is never stored
/// as the user's stated reason.
nonisolated enum SessionMode: String, CaseIterable, Identifiable, Sendable {
    case ask
    case teach
    case debug
    case prep

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ask: "Ask"
        case .teach: "Teach"
        case .debug: "Debug"
        case .prep: "Prep"
        }
    }

    var help: String {
        switch self {
        case .ask: "Straight answers about what is on screen."
        case .teach: "Step-by-step lessons with boxes and spoken beats."
        case .debug: "Lead with the failure, then the smallest fix."
        case .prep: "Briefs from keeps and tasks — standup / project."
        }
    }

    /// Whether pressing Return in this mode should start a lesson walk when
    /// the answer is a numbered list with quotes.
    var prefersTeaching: Bool { self == .teach }

    /// Whether Explain-style boards are welcome by default.
    var prefersBoard: Bool { self == .teach || self == .ask }

    /// Extra system guidance for this stance.
    var guidance: String {
        switch self {
        case .ask:
            """
            Session mode is Ask: answer the question directly. Be brief. Quote on-screen \
            labels when you name a control. Do not turn a yes/no into a lesson unless asked.
            """

        case .teach:
            """
            Session mode is Teach: prefer a short numbered walk when the screen has something \
            to learn from. Quote what you point at. Lead each step with why, then the quote. \
            Follow-ups continue the same lesson voice.
            """

        case .debug:
            """
            Session mode is Debug: lead with what is wrong and why, in one or two sentences. \
            Then the smallest next action — one command or one change — in a fenced block when \
            it is a command. Quote the failing line or message exactly. Do not walk the whole \
            file unless asked.
            """

        case .prep:
            """
            Session mode is Prep: summarise from the user's own keeps and open tasks first. \
            Do not invent work. Prefer bullets they can paste into a standup. If the screen \
            is relevant, connect it to a kept note or task by name.
            """
        }
    }
}

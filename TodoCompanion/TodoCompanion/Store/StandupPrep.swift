import Foundation

/// Assembles a standup / meeting-prep question from local state.
///
/// User-initiated only — never scheduled. Pure so the wording is testable.
nonisolated enum StandupPrep {
    static func askPrompt(projectName: String?,
                          openTaskTitles: [String],
                          dueSoonIntents: [String],
                          recentKeepIntents: [String]) -> String {
        var sections: [String] = [
            """
            Help me prepare a short standup update. Use only the facts below. \
            Structure as: yesterday / today / blockers. Keep it under eight \
            sentences. Do not invent work I did not list.
            """,
        ]

        if let projectName, !projectName.isEmpty {
            sections.append("Current project: \(projectName)")
        }

        let tasks = openTaskTitles.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !tasks.isEmpty {
            sections.append("Open tasks:\n" + tasks.prefix(8).map { "- \($0)" }.joined(separator: "\n"))
        }

        let due = dueSoonIntents.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !due.isEmpty {
            sections.append("Due soon / overdue:\n" + due.prefix(6).map { "- \($0)" }.joined(separator: "\n"))
        }

        let keeps = recentKeepIntents.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if !keeps.isEmpty {
            sections.append("Screens I kept recently:\n" + keeps.prefix(6).map { "- \($0)" }.joined(separator: "\n"))
        }

        if tasks.isEmpty && due.isEmpty && keeps.isEmpty {
            sections.append("(No tasks or saves linked yet — ask me what I worked on, then draft the update.)")
        }

        return sections.joined(separator: "\n\n")
    }
}

import Foundation

/// A one-page draft of what the user has been doing in a project.
///
/// Assembled from *their* intents and open tasks — never from model gloss —
/// then offered as the question Max should expand. The user still owns the
/// words that get saved; this only proposes.
nonisolated enum ProjectBrief {
    /// Builds the ask string for Max, or nil when there is nothing to say.
    static func askPrompt(projectName: String,
                          intents: [String],
                          openTaskTitles: [String],
                          dueSoonIntents: [String] = []) -> String? {
        let cleanedIntents = intents
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let tasks = openTaskTitles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let due = dueSoonIntents
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !cleanedIntents.isEmpty || !tasks.isEmpty || !due.isEmpty else { return nil }

        var sections: [String] = []
        sections.append("""
        Draft a short project brief for “\(projectName)” I can skim before \
        continuing work. Use only what I listed — do not invent tasks or \
        conclusions. End with one concrete next step.
        """)

        if !cleanedIntents.isEmpty {
            let bullets = cleanedIntents.prefix(12).map { "- \($0)" }.joined(separator: "\n")
            sections.append("Why I kept screens:\n\(bullets)")
        }
        if !tasks.isEmpty {
            let bullets = tasks.prefix(10).map { "- \($0)" }.joined(separator: "\n")
            sections.append("Open tasks in the to-do app:\n\(bullets)")
        }
        if !due.isEmpty {
            let bullets = due.prefix(6).map { "- \($0)" }.joined(separator: "\n")
            sections.append("Reminders due soon:\n\(bullets)")
        }

        return sections.joined(separator: "\n\n")
    }
}

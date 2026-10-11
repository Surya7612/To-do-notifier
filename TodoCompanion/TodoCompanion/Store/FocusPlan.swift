import Foundation

/// "I have 45 minutes — what should I work on?"
///
/// The to-do app records no durations, so nothing here can know what fits in
/// a stated budget, and pretending otherwise would be the app presenting a
/// guess as a fact. What it can do is hand the model the open tasks in a
/// defensible order — overdue, then due soonest — with the budget the user
/// stated, and require it to say that any judgement of length is its own.
/// Pure so the wording and the parse are testable.
nonisolated enum FocusPlan {
    /// Whether the question asks what to do next.
    static func isPlanningQuestion(_ question: String) -> Bool {
        let text = question.lowercased()
        return patterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private static let patterns = [
        #"\bwhat\s+(should|shall|could|can|do)\s+i\s+(work\s+on|do|tackle|focus\s+on|start\s+(on|with)|pick|get\s+done)\b"#,
        #"\bwhat\s+to\s+(work\s+on|do|tackle|focus\s+on)\b"#,
        #"\bwhere\s+should\s+i\s+start\b"#,
        #"\bwhat'?s\s+next\s+for\s+me\b"#,
        #"\bplan\s+my\s+(next|day|afternoon|morning|evening|hour)\b"#,
    ]

    /// Minutes the question says are available, if it says.
    static func minutes(in question: String) -> Int? {
        let text = question.lowercased()

        if text.range(of: #"\b(an|one)\s+hour\s+and\s+a\s+half\b"#, options: .regularExpression) != nil {
            return 90
        }
        if text.range(of: #"\bhalf\s+an\s+hour\b"#, options: .regularExpression) != nil {
            return 30
        }
        if let hours = capture(#"\b(\d+(?:\.\d+)?)\s*(?:h|hr|hrs|hour|hours)\b"#, in: text),
           let value = Double(hours), value > 0 {
            return Int((value * 60).rounded())
        }
        if let mins = capture(#"\b(\d+)\s*(?:m|min|mins|minute|minutes)\b"#, in: text),
           let value = Int(mins), value > 0 {
            return value
        }
        if text.range(of: #"\b(an|one)\s+hour\b"#, options: .regularExpression) != nil {
            return 60
        }
        if text.range(of: #"\bnext\s+hour\b"#, options: .regularExpression) != nil {
            return 60
        }
        return nil
    }

    /// The paragraph the model is given alongside the task list.
    static func note(minutes: Int?, hasTasks: Bool, projectName: String?) -> String {
        guard hasTasks else {
            return """
            The user is asking what to work on next, and no open tasks are linked from their \
            to-do app. Say so in one sentence, then ask what they want to get done — do not \
            invent tasks.
            """
        }

        let budget = minutes.map { "They have about \(Self.describe(minutes: $0))." } ?? ""
        let project = projectName.map { " They said they are working on \($0); prefer its tasks." } ?? ""
        return """
        The user is asking what to work on next. \(budget)\(project) Choose only from the open \
        tasks listed below, quoting each title exactly as written. Overdue tasks come first, \
        then whatever is due soonest. Suggest one main task and at most two small ones. Task \
        lengths are not recorded anywhere, so if you judge what fits the time, say that the \
        estimate is yours. Keep it to a short list and a sentence on why.
        """
    }

    static func describe(minutes: Int) -> String {
        switch minutes {
        case ..<60: return "\(minutes) minutes"
        case 60: return "an hour"
        default:
            let hours = minutes / 60
            let rest = minutes % 60
            let hourText = hours == 1 ? "1 hour" : "\(hours) hours"
            return rest == 0 ? hourText : "\(hourText) \(rest) minutes"
        }
    }

    private static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}

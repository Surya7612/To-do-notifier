import Foundation

/// Answers "what did I keep?" from the question rather than from the screen.
///
/// `ContextRetriever` scores against what is visible, which is right for
/// resurfacing and wrong for recall: "what was I researching yesterday?" says
/// nothing about the window it is asked over, so screen-keyed retrieval found
/// nothing and the model, shown no keeps, could only say so or invent some.
/// Every match carries a reason like the rest of retrieval — a time window
/// matched, a word matched — so a recalled keep explains itself.
enum LibraryRecall {
    /// A span of time named in the question, with the words that named it.
    nonisolated struct TimeWindow: Equatable {
        let interval: DateInterval
        let phrase: String
    }

    static let limit = 8

    /// Whether the question is about the user's own past keeps.
    ///
    /// Deliberately needs the *past*: "did I save", "I kept", "what was I
    /// working on", or a possessive like "my saves". The present tense is how
    /// people ask about the screen — "how do I save this?", "what should I
    /// work on?" — and treating those as recall would bury the answer under a
    /// list nobody asked for.
    nonisolated static func isRecallQuestion(_ question: String) -> Bool {
        let text = question.lowercased()
        return recallPatterns.contains { text.range(of: $0, options: .regularExpression) != nil }
    }

    private nonisolated static let recallPatterns = [
        #"\b(did|have|had)\s+i\b[^.?!]{0,30}\b(save|keep|note|stash|bookmark|capture|look|read|research|work|do)\b"#,
        #"\bi(\s+had|'d|\s+have|'ve)?\s+(saved|kept|noted|stashed|bookmarked|captured|researched)\b"#,
        #"\b(was|were)\s+(i|we)\s+(researching|working|looking|reading|trying|doing|solving)\b"#,
        #"\bi\s+was\s+(researching|working|looking|reading|trying|doing|solving)\b"#,
        #"\bmy\s+(saves|keeps|notes|library|captures|screenshots)\b"#,
    ]

    /// The span of time a question names, or nil if it names none.
    ///
    /// Intervals end at `now` for the current period rather than at its end,
    /// so "this week" never claims to have looked at days that have not
    /// happened.
    nonisolated static func timeWindow(in question: String,
                                       now: Date = Date(),
                                       calendar: Calendar = .current) -> TimeWindow? {
        let text = question.lowercased()
        let startOfToday = calendar.startOfDay(for: now)

        func window(_ start: Date, _ end: Date, _ phrase: String) -> TimeWindow? {
            guard end > start else { return nil }
            return TimeWindow(interval: DateInterval(start: start, end: end), phrase: phrase)
        }

        if let match = firstMatch(#"\b(?:past|last)\s+(\d{1,3})\s+days?\b"#, in: text),
           let days = Int(match), days > 0,
           let start = calendar.date(byAdding: .day, value: -days, to: startOfToday) {
            return window(start, now, "in the last \(days) days")
        }
        if let match = firstMatch(#"\b(\d{1,3})\s+days?\s+ago\b"#, in: text),
           let days = Int(match), days > 0,
           let start = calendar.date(byAdding: .day, value: -days, to: startOfToday),
           let end = calendar.date(byAdding: .day, value: 1, to: start) {
            return window(start, end, "\(days) days ago")
        }
        if contains(#"\byesterday\b"#, text),
           let start = calendar.date(byAdding: .day, value: -1, to: startOfToday) {
            return window(start, startOfToday, "yesterday")
        }
        if contains(#"\b(today|this morning|this afternoon|tonight|earlier)\b"#, text) {
            return window(startOfToday, now, "today")
        }
        if contains(#"\blast\s+week\b"#, text),
           let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now),
           let start = calendar.date(byAdding: .weekOfYear, value: -1, to: thisWeek.start) {
            return window(start, thisWeek.start, "last week")
        }
        if contains(#"\bthis\s+week\b"#, text),
           let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now) {
            return window(thisWeek.start, now, "this week")
        }
        if contains(#"\blast\s+month\b"#, text),
           let thisMonth = calendar.dateInterval(of: .month, for: now),
           let start = calendar.date(byAdding: .month, value: -1, to: thisMonth.start) {
            return window(start, thisMonth.start, "last month")
        }
        if contains(#"\bthis\s+month\b"#, text),
           let thisMonth = calendar.dateInterval(of: .month, for: now) {
            return window(thisMonth.start, now, "this month")
        }
        if let weekday = weekdayWindow(in: text, now: now, calendar: calendar) {
            return weekday
        }
        if contains(#"\b(recently|lately)\b"#, text),
           let start = calendar.date(byAdding: .day, value: -7, to: startOfToday) {
            return window(start, now, "in the last week")
        }
        return nil
    }

    /// "On Monday" or "last friday" means the most recent such day before
    /// today, never today itself — someone asking about Monday on a Monday
    /// would say "today".
    private nonisolated static func weekdayWindow(in text: String,
                                                  now: Date,
                                                  calendar: Calendar) -> TimeWindow? {
        let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
        guard let name = firstMatch(#"\b(?:on|last)\s+(sunday|monday|tuesday|wednesday|thursday|friday|saturday)\b"#,
                                    in: text),
              let index = names.firstIndex(of: name)
        else { return nil }

        let startOfToday = calendar.startOfDay(for: now)
        let today = calendar.component(.weekday, from: now)
        var back = (today - (index + 1) + 7) % 7
        if back == 0 { back = 7 }
        guard let start = calendar.date(byAdding: .day, value: -back, to: startOfToday),
              let end = calendar.date(byAdding: .day, value: 1, to: start)
        else { return nil }
        return TimeWindow(interval: DateInterval(start: start, end: end),
                          phrase: "on \(name.capitalized)")
    }

    /// Whether the question narrows itself to the current project.
    nonisolated static func scopesToCurrentProject(_ question: String) -> Bool {
        contains(#"\b(this|current|the)\s+project\b"#, question.lowercased())
    }

    /// Keeps that answer the question, best first.
    ///
    /// A time window or project scope is a filter, not a score: a keep from
    /// last week is not a weaker answer to "yesterday", it is not an answer.
    /// Within the filter, words of the question that are about the subject
    /// rather than about recalling rank what is left; a question with no such
    /// words ("what did I save yesterday?") gets everything in the window,
    /// newest first.
    static func matches(for question: String,
                        among candidates: [SavedContext],
                        inProject currentProject: Project? = nil,
                        now: Date = Date(),
                        calendar: Calendar = .current) -> [RetrievalMatch] {
        guard isRecallQuestion(question) else { return [] }

        let window = timeWindow(in: question, now: now, calendar: calendar)
        let project = scopesToCurrentProject(question) ? currentProject : nil
        let subject = subjectWords(in: question)

        var results: [RetrievalMatch] = []
        for candidate in candidates {
            if let window, !window.interval.contains(candidate.createdAt) { continue }
            if let project, candidate.project?.identifier != project.identifier { continue }

            var reasons: [String] = []
            if let window { reasons.append("kept \(window.phrase)") }
            if let project { reasons.append("in \(project.name)") }

            var score = 0.0
            if !subject.isEmpty {
                let stated = tokens(in: [candidate.intent, candidate.topics.joined(separator: " ")]
                    .joined(separator: " "))
                let described = tokens(in: [candidate.aiSummary, candidate.windowTitle, candidate.sourceApp]
                    .joined(separator: " "))
                let statedHits = subject.intersection(stated)
                let describedHits = subject.intersection(described).subtracting(statedHits)
                // The user's own words count for more than the model's gloss or
                // the window title, the same ordering retrieval uses everywhere.
                score = 2.0 * Double(statedHits.count) + Double(describedHits.count)
                guard score > 0 else { continue }
                reasons.append("mentions \(statedHits.union(describedHits).sorted().prefix(2).joined(separator: ", "))")
            } else if window == nil, project == nil {
                // Bare "what did I save?" — the honest answer is the most
                // recent keeps, and saying so.
                reasons.append("recent")
            }

            results.append(RetrievalMatch(context: candidate, score: score, reason: reasons.joined(separator: " · ")))
        }

        return results
            .sorted { lhs, rhs in
                lhs.score != rhs.score ? lhs.score > rhs.score : lhs.context.createdAt > rhs.context.createdAt
            }
            .prefix(limit)
            .map { $0 }
    }

    /// What the model is told about the search, so an empty result is said
    /// plainly rather than papered over with invented keeps.
    nonisolated static func scopeNote(for question: String,
                                      found: Int,
                                      projectName: String?,
                                      now: Date = Date(),
                                      calendar: Calendar = .current) -> String {
        var scope: [String] = []
        if let window = timeWindow(in: question, now: now, calendar: calendar) {
            scope.append("kept \(window.phrase)")
        }
        if scopesToCurrentProject(question), let projectName {
            scope.append("in the project \(projectName)")
        }
        let described = scope.isEmpty ? "matching the question" : scope.joined(separator: ", ")
        return found == 0
            ? "The user is asking about what they kept. A search of their library for keeps \(described) found nothing. Say so plainly; do not invent any."
            : "The user is asking about what they kept. A search of their library for keeps \(described) found \(found), listed below in their own words. Answer from those, and do not invent others."
    }

    private nonisolated static let recallWords: Set<String> = [
        "what", "which", "did", "was", "were", "have", "had", "show", "list", "find", "tell",
        "anything", "something", "things", "stuff", "everything", "all",
        "save", "saved", "saving", "keep", "kept", "keeping", "note", "noted", "stash", "stashed",
        "bookmark", "bookmarked", "research", "researched", "researching", "work", "worked",
        "working", "look", "looked", "looking", "read", "reading", "revisit", "trying", "try",
        "tried", "solve", "solving", "remind", "remember", "for", "about", "on", "from", "the",
        "and", "with", "this", "that", "these", "those", "my", "me", "you", "your", "i've", "i'd",
        "saves", "keeps", "notes", "library", "captures", "screenshots", "project", "current",
        "today", "yesterday", "week", "month", "last", "past", "days", "day", "ago", "recently",
        "lately", "morning", "afternoon", "tonight", "earlier", "sunday", "monday", "tuesday",
        "wednesday", "thursday", "friday", "saturday", "again", "back", "then", "when", "where",
    ]

    /// The words of a question that name a subject.
    nonisolated static func subjectWords(in question: String) -> Set<String> {
        tokens(in: question).subtracting(recallWords)
    }

    private nonisolated static func tokens(in text: String) -> Set<String> {
        Set(
            text.lowercased()
                .split { !$0.isLetter && !$0.isNumber && $0 != "'" }
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "'")) }
                .filter { $0.count > 2 && !$0.allSatisfy(\.isNumber) }
        )
    }

    private nonisolated static func contains(_ pattern: String, _ text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }

    private nonisolated static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
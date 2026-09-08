import Foundation

/// A time this text might be asking to be reminded at.
struct ReminderSuggestion: Equatable, Sendable {
    let date: Date

    /// True when the user actually asked to be reminded, rather than merely
    /// mentioning a time. Only an explicit request may arm a reminder by
    /// default; a bare date is offered but left switched off, because reading a
    /// date out of someone's sentence is inference and inference does not get
    /// to act on its own.
    let wasExplicitlyRequested: Bool

    /// The words the date came from, so the panel can show its reading rather
    /// than presenting a time the user never typed as though they had.
    let matchedText: String?
}

/// Decides whether a saved reason is asking to be brought back later, and when.
///
/// Kept free of the notification machinery so the question "does this sentence
/// ask for a reminder?" can be answered without a permission prompt or a clock.
enum ReminderPhrase {
    /// Phrasings that mean the user wants this back, independent of any date.
    ///
    /// Deliberately verbs and not time words: "notes from tomorrow's standup"
    /// mentions a day without asking for anything.
    private static let requestCues = [
        "remind me", "reminder", "follow up", "follow-up", "followup",
        "come back to", "circle back", "revisit", "get back to",
        "don't forget", "dont forget", "do not forget",
        "check back", "look at this later", "deal with this later",
        "todo", "to-do", "to do",
    ]

    /// When a request has no time in it, morning is the least intrusive guess.
    private static let defaultHour = 9

    nonisolated static func suggestion(in text: String,
                                       now: Date = Date(),
                                       calendar: Calendar = .current) -> ReminderSuggestion? {
        let lowered = text.lowercased()
        let wasExplicitlyRequested = requestCues.contains { lowered.contains($0) }

        if let found = firstFutureDate(in: text, now: now, calendar: calendar) {
            return ReminderSuggestion(date: found.date,
                                      wasExplicitlyRequested: wasExplicitlyRequested,
                                      matchedText: found.matchedText)
        }

        // Asked to be reminded but never said when.
        guard wasExplicitlyRequested,
              let tomorrowMorning = nextMorning(after: now, calendar: calendar)
        else { return nil }

        return ReminderSuggestion(date: tomorrowMorning,
                                  wasExplicitlyRequested: true,
                                  matchedText: nil)
    }

    /// Uses the system's own date parser rather than a hand-rolled one, so
    /// "next tuesday at 4" and "in three days" work without this file growing a
    /// calendar of its own.
    ///
    /// Note that `NSDataDetector` takes no reference date: relative words are
    /// always resolved against the system clock, whatever `now` says. `now` is
    /// still honoured for rejecting past dates and for the fallback time.
    private nonisolated static func firstFutureDate(
        in text: String,
        now: Date,
        calendar: Calendar
    ) -> (date: Date, matchedText: String)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
        else { return nil }

        let range = NSRange(text.startIndex..., in: text)

        for match in detector.matches(in: text, options: [], range: range) {
            guard let parsed = match.date else { continue }

            let matchedText = Range(match.range, in: text).map { String(text[$0]) } ?? ""
            let resolved = normalizeTimeOfDay(parsed, statedIn: matchedText, calendar: calendar)

            // "notes from yesterday" is a description, not a request.
            guard resolved > now else { continue }

            return (resolved, matchedText)
        }

        return nil
    }

    /// "tomorrow" carries no time, and whatever the detector fills in — often
    /// midnight — would fire while the user is asleep. `NSTextCheckingResult`
    /// does not expose whether a time was actually stated, so the matched words
    /// are the only evidence available.
    private nonisolated static func normalizeTimeOfDay(_ date: Date,
                                                       statedIn matchedText: String,
                                                       calendar: Calendar) -> Date {
        let lowered = matchedText.lowercased()

        if statesAClockTime(lowered) { return date }

        let hour = ["tonight", "evening", "afternoon"].contains(where: lowered.contains)
            ? 18
            : defaultHour

        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
    }

    /// Matches a digit next to a colon or an am/pm marker, plus the two named
    /// times of day. Substring checks are not enough: "am" appears inside plenty
    /// of ordinary words.
    private nonisolated static let clockTime = try? NSRegularExpression(
        pattern: #"\d\s*(?::\d|[ap]\.?\s?m\.?)|\bnoon\b|\bmidnight\b|o'clock"#,
        options: [.caseInsensitive]
    )

    private nonisolated static func statesAClockTime(_ text: String) -> Bool {
        guard let clockTime else { return false }
        return clockTime.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private nonisolated static func nextMorning(after now: Date, calendar: Calendar) -> Date? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        return calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: tomorrow)
    }
}

/// The handful of times worth offering as one tap, for when the guessed time is
/// not the wanted one.
enum ReminderPreset: String, CaseIterable, Identifiable, Sendable {
    case inAnHour = "In an hour"
    case thisEvening = "This evening"
    case tomorrowMorning = "Tomorrow morning"
    case nextWeek = "Next week"

    var id: String { rawValue }

    nonisolated func date(from now: Date = Date(), calendar: Calendar = .current) -> Date? {
        switch self {
        case .inAnHour:
            return calendar.date(byAdding: .hour, value: 1, to: now)

        case .thisEvening:
            let evening = calendar.date(bySettingHour: 18, minute: 0, second: 0, of: now)
            // Past six already, so "this evening" can only mean the next one.
            guard let evening, evening > now else {
                return calendar.date(byAdding: .day, value: 1, to: now)
                    .flatMap { calendar.date(bySettingHour: 18, minute: 0, second: 0, of: $0) }
            }
            return evening

        case .tomorrowMorning:
            return calendar.date(byAdding: .day, value: 1, to: now)
                .flatMap { calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0) }

        case .nextWeek:
            return calendar.date(byAdding: .day, value: 7, to: now)
                .flatMap { calendar.date(bySettingHour: 9, minute: 0, second: 0, of: $0) }
        }
    }
}

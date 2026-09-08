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
nonisolated enum ReminderPhrase {
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

    static func suggestion(in text: String,
                                       now: Date = Date(),
                                       calendar: Calendar = .current) -> ReminderSuggestion? {
        let lowered = text.lowercased()
        let wasExplicitlyRequested = requestCues.contains { lowered.contains($0) }

        // Before the system parser, not after it. A stated duration is the
        // user saying when they want this back; a clock time elsewhere in the
        // sentence is usually part of what they are describing — "remind me in
        // an hour about the 3pm meeting" means an hour, not three.
        if let found = relativeDuration(in: text, now: now, calendar: calendar) {
            return ReminderSuggestion(date: found.date,
                                      wasExplicitlyRequested: wasExplicitlyRequested,
                                      matchedText: found.matchedText)
        }

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

    /// Durations the system parser does not recognize at all.
    ///
    /// Measured, not assumed. `NSDataDetector` matches "in 3 days" and "in 2
    /// weeks", and **nothing below a day**: not "in an hour", not "in 10 min",
    /// not "in 90 seconds". It also needs digits, so "in three days" and "in a
    /// week" fail too. "Remind me to send an email in one minute" therefore
    /// found no time at all, was offered as tomorrow morning by the fallback,
    /// and — because the fallback states no time — was not treated as an
    /// instruction either, so it went to the model, which explained that it
    /// could not set reminders. Every part of that was this gap.
    private static let durationPattern = try? NSRegularExpression(
        pattern: #"\bin\s+(half\s+an?|\d{1,4}|[a-z]+(?:[-\s]five)?)\s+"#
            + #"(seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|weeks?)\b"#,
        options: [.caseInsensitive]
    )

    /// Spelled-out amounts, which the system parser rejects outright.
    private static let amountWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5,
        "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11,
        "twelve": 12, "fifteen": 15, "twenty": 20, "thirty": 30, "forty": 40,
        "forty-five": 45, "forty five": 45, "sixty": 60, "ninety": 90,
    ]

    private static func component(forUnit unit: String) -> Calendar.Component? {
        switch unit {
        case _ where unit.hasPrefix("sec"): .second
        case _ where unit.hasPrefix("min"): .minute
        case _ where unit.hasPrefix("hr"), _ where unit.hasPrefix("hour"): .hour
        case _ where unit.hasPrefix("day"): .day
        case _ where unit.hasPrefix("week"): .weekOfYear
        default: nil
        }
    }

    private static func relativeDuration(
        in text: String,
        now: Date,
        calendar: Calendar
    ) -> (date: Date, matchedText: String)? {
        guard let durationPattern else { return nil }

        let range = NSRange(text.startIndex..., in: text)

        // Every match is tried rather than just the first, because the amount
        // group deliberately accepts any word: "in the minutes that follow"
        // matches the shape and resolves to nothing, and should not stop a real
        // duration later in the sentence from being found.
        for match in durationPattern.matches(in: text, options: [], range: range) {
            guard let amountRange = Range(match.range(at: 1), in: text),
                  let unitRange = Range(match.range(at: 2), in: text),
                  let matchedRange = Range(match.range, in: text)
            else { continue }

            let amountText = text[amountRange].lowercased()
            let unit = text[unitRange].lowercased()
            guard let component = component(forUnit: unit) else { continue }

            // "half an hour" is thirty minutes, not half of one hour, because
            // `Calendar` moves in whole units.
            let isHalf = amountText.hasPrefix("half")
            let amount = isHalf ? 1 : (Int(amountText) ?? amountWords[amountText])
            guard let amount, amount > 0 else { continue }

            let resolved: Date? = if isHalf {
                halved(component, from: now, calendar: calendar)
            } else {
                calendar.date(byAdding: component, value: amount, to: now)
            }

            guard var date = resolved, date > now else { continue }

            // A duration of days or more states no time of day, so it gets the
            // same morning treatment a bare "friday" does. Anything shorter
            // means exactly what it says and must not be moved.
            if component == .day || component == .weekOfYear {
                date = calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: date)
                    ?? date
            }

            return (date, String(text[matchedRange]))
        }

        return nil
    }

    /// "half an hour" and "half a day", in the next unit down.
    private static func halved(_ component: Calendar.Component,
                               from now: Date,
                               calendar: Calendar) -> Date? {
        switch component {
        case .hour: calendar.date(byAdding: .minute, value: 30, to: now)
        case .minute: calendar.date(byAdding: .second, value: 30, to: now)
        case .day: calendar.date(byAdding: .hour, value: 12, to: now)
        case .weekOfYear: calendar.date(byAdding: .day, value: 3, to: now)
        default: nil
        }
    }

    /// Uses the system's own date parser for absolute dates, so "next tuesday
    /// at 4" and "in 3 days" work without this file growing a calendar of its
    /// own. What it cannot do is handled above.
    ///
    /// Note that `NSDataDetector` takes no reference date: relative words are
    /// always resolved against the system clock, whatever `now` says. `now` is
    /// still honoured for rejecting past dates and for the fallback time.
    private static func firstFutureDate(
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
    private static func normalizeTimeOfDay(_ date: Date,
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
    private static let clockTime = try? NSRegularExpression(
        pattern: #"\d\s*(?::\d|[ap]\.?\s?m\.?)|\bnoon\b|\bmidnight\b|o'clock"#,
        options: [.caseInsensitive]
    )

    private static func statesAClockTime(_ text: String) -> Bool {
        guard let clockTime else { return false }
        return clockTime.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func nextMorning(after now: Date, calendar: Calendar) -> Date? {
        guard let tomorrow = calendar.date(byAdding: .day, value: 1, to: now) else { return nil }
        return calendar.date(bySettingHour: defaultHour, minute: 0, second: 0, of: tomorrow)
    }
}

/// The handful of times worth offering as one tap, for when the guessed time is
/// not the wanted one.
nonisolated enum ReminderPreset: String, CaseIterable, Identifiable, Sendable {
    case inAnHour = "In an hour"
    case thisEvening = "This evening"
    case tomorrowMorning = "Tomorrow morning"
    case nextWeek = "Next week"

    var id: String { rawValue }

    func date(from now: Date = Date(), calendar: Calendar = .current) -> Date? {
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

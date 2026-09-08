import Foundation
import Testing
@testable import TodoCompanion

/// What counts as asking to be reminded, and what time that means.
///
/// The distinction these tests protect is not "did it find a date" but whether
/// the user *asked*. An explicit request may arm a reminder by itself; a date
/// merely mentioned in passing may only offer one. Getting that backwards would
/// mean the app acting on its own reading of a sentence.
@Suite("Reminder phrasing")
struct ReminderPhraseTests {
    /// The real clock, deliberately.
    ///
    /// `NSDataDetector` has no reference-date parameter and always resolves
    /// "tomorrow" against the system clock, so handing this a pinned `now` in
    /// the past makes a real yesterday look like the future. These assertions
    /// are therefore relative — tomorrow is tomorrow, nine is nine — rather
    /// than fixed timestamps.
    private let now = Date()
    private let calendar = Calendar(identifier: .gregorian)

    private func suggestion(_ text: String) -> ReminderSuggestion? {
        ReminderPhrase.suggestion(in: text, now: now, calendar: calendar)
    }

    /// Whether pressing Return carries the instruction out instead of asking the
    /// model about it. `CompanionViewModel.isReminderInstruction` is the same
    /// two conditions, and this covers the parser's half of it.
    ///
    /// Typing "Remind me to text voice bugs at 10 AM today" used to be answered
    /// by the model explaining how to create a reminder in some other app — the
    /// app declining to do what it had plainly been told. The line is drawn at
    /// an explicit cue *and* a stated time, so a question that happens to
    /// contain "remind me" is still a question.
    ///
    /// The reported sentence said "today", and the test deliberately does not:
    /// a stated hour that has already passed is rejected by design, so the
    /// original wording made this pass before 10 AM and fail after it. What is
    /// under test is a stated clock time, not which day it lands on.
    @Test("an explicit cue with a stated time is an instruction")
    func instructionNeedsBothCueAndTime() throws {
        let instruction = try #require(suggestion("remind me to text voice bugs tomorrow at 10 AM"))
        #expect(instruction.wasExplicitlyRequested)
        #expect(instruction.matchedText != nil, "the time has to come from the sentence")

        // No time stated, so the parser falls back to a guess. That guess may
        // be offered, but it must not be treated as a command.
        let question = try #require(suggestion("remind me what a closure is"))
        #expect(question.wasExplicitlyRequested)
        #expect(question.matchedText == nil, "a fallback time is not a stated one")
    }

    @Test("asking to be reminded, with a day, is an explicit request")
    func explicitRequestWithDate() throws {
        let result = try #require(suggestion("remind me to follow up on this tomorrow"))

        #expect(result.wasExplicitlyRequested)
        #expect(result.matchedText?.contains("tomorrow") == true)
    }

    @Test("asking to be reminded with no day still gets a time")
    func explicitRequestWithoutDate() throws {
        let result = try #require(suggestion("remind me about this"))

        #expect(result.wasExplicitlyRequested)
        #expect(result.matchedText == nil, "nothing in the text produced this time")
        #expect(result.date > now)
    }

    @Test("several phrasings all read as a request")
    func recognizesCommonPhrasings() throws {
        for phrasing in ["follow up on this", "come back to this", "don't forget this",
                         "revisit this", "circle back on this", "todo: read this"] {
            let result = try #require(suggestion(phrasing), "\(phrasing) should be a request")
            #expect(result.wasExplicitlyRequested, "\(phrasing) should be explicit")
        }
    }

    /// The important negative case. A date in a description is not a request,
    /// so it may be offered but must not arm itself.
    @Test("mentioning a day without asking is not an explicit request")
    func dateAloneIsNotARequest() throws {
        let result = try #require(suggestion("notes from tomorrow's standup"))

        #expect(result.wasExplicitlyRequested == false)
        #expect(result.date > now)
    }

    @Test("an ordinary reason asks for nothing")
    func plainReasonSuggestsNothing() {
        #expect(suggestion("the retrieval scoring weights") == nil)
        #expect(suggestion("a screenshot of the settings pane") == nil)
    }

    @Test("empty and whitespace text suggest nothing")
    func emptyTextSuggestsNothing() {
        #expect(suggestion("") == nil)
        #expect(suggestion("   ") == nil)
    }

    @Test("a day with no time attached lands in the morning, not at midnight")
    func daysWithoutTimesBecomeMorning() throws {
        let result = try #require(suggestion("remind me tomorrow"))
        let hour = calendar.component(.hour, from: result.date)

        #expect(hour == 9, "midnight would fire while the user is asleep")
    }

    @Test("a stated time is kept as stated")
    func explicitTimeIsRespected() throws {
        let result = try #require(suggestion("remind me tomorrow at 4pm"))

        #expect(calendar.component(.hour, from: result.date) == 16)
        #expect(calendar.isDateInTomorrow(result.date))
    }

    /// "notes from yesterday" would otherwise produce a reminder in the past,
    /// which can never fire.
    @Test("a date already gone is ignored")
    func pastDatesAreIgnored() {
        #expect(suggestion("screenshot from yesterday's meeting") == nil)
        #expect(suggestion("notes from last week") == nil)
    }

    @Test("a past date does not stop an explicit request from getting a time")
    func explicitRequestSurvivesAPastDate() throws {
        let result = try #require(suggestion("remind me to redo the notes from yesterday"))

        #expect(result.wasExplicitlyRequested)
        #expect(result.date > now)
    }

    @Test("cues are found regardless of capitalisation")
    func cuesAreCaseInsensitive() throws {
        #expect(try #require(suggestion("Remind Me about this")).wasExplicitlyRequested)
        #expect(try #require(suggestion("FOLLOW UP on this")).wasExplicitlyRequested)
    }
}

@Suite("Reminder presets")
struct ReminderPresetTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test("every preset lands in the future")
    func presetsAreAlwaysFuture() throws {
        // Checked across the day because "this evening" depends on the hour.
        for hour in [0, 8, 12, 17, 19, 23] {
            let now = try #require(calendar.date(bySettingHour: hour, minute: 30, second: 0, of: Date()))

            for preset in ReminderPreset.allCases {
                let date = try #require(preset.date(from: now, calendar: calendar),
                                        "\(preset.rawValue) produced no date")
                #expect(date > now, "\(preset.rawValue) at \(hour):30 was not in the future")
            }
        }
    }

    @Test("this evening means tonight, unless tonight has passed")
    func eveningRollsOverAfterSix() throws {
        let morning = try #require(calendar.date(bySettingHour: 9, minute: 0, second: 0, of: Date()))
        let evening = try #require(ReminderPreset.thisEvening.date(from: morning, calendar: calendar))
        #expect(calendar.isDate(evening, inSameDayAs: morning))

        let lateNight = try #require(calendar.date(bySettingHour: 22, minute: 0, second: 0, of: Date()))
        let next = try #require(ReminderPreset.thisEvening.date(from: lateNight, calendar: calendar))
        #expect(!calendar.isDate(next, inSameDayAs: lateNight), "10pm is past this evening")
    }

    @Test("tomorrow morning is the next day, in the morning")
    func tomorrowMorningIsTomorrow() throws {
        let now = Date()
        let date = try #require(ReminderPreset.tomorrowMorning.date(from: now, calendar: calendar))

        #expect(calendar.isDateInTomorrow(date))
        #expect(calendar.component(.hour, from: date) == 9)
    }
}

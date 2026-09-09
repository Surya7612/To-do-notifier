import Foundation
import Testing
@testable import TodoCompanion

/// The manifest is written by a Shortcut on a phone, over a syncing folder,
/// and nothing here compiles against it. So every shape of malformed input has
/// to produce "not an item" rather than a save with garbage in it — a bad
/// import is persisted and then resurfaces later, which is worse than an import
/// that did not happen.
@Suite("Inbox import")
struct InboxImporterTests {
    private func parse(_ object: [String: Any], now: Date = Date()) -> InboxItem? {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return InboxImporter.parse(data, fallbackDate: now)
    }

    private let onePixelPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    )!

    @Test("a reason and an image come through")
    func readsAReasonAndImage() throws {
        let item = try #require(parse([
            "intent": "check this when I redo retrieval",
            "imageBase64": onePixelPNG.base64EncodedString(),
            "createdAt": "2026-09-07T14:30:00Z",
            "source": "iPhone",
        ]))

        #expect(item.intent == "check this when I redo retrieval")
        #expect(item.imageData == onePixelPNG)
        #expect(item.source == "iPhone")
    }

    /// A thought captured on a walk is exactly what phone capture is for, so an
    /// image is not required.
    @Test("a reason with no image is still worth keeping")
    func acceptsAReasonAlone() throws {
        let item = try #require(parse(["intent": "look up how Engram scores recency"]))

        #expect(item.imageData == nil)
        #expect(item.intent == "look up how Engram scores recency")
    }

    /// The reason is the thing this app is built around. Importing a screenshot
    /// with no reason and inventing one later would be inference posing as the
    /// user's own words.
    @Test("an image with no reason is refused")
    func refusesAnImageWithNoReason() {
        #expect(parse(["imageBase64": onePixelPNG.base64EncodedString()]) == nil)
        #expect(parse(["intent": "   "]) == nil)
        #expect(parse(["intent": ""]) == nil)
        #expect(parse([:]) == nil)
    }

    @Test("garbage is not an item")
    func refusesGarbage() {
        #expect(InboxImporter.parse(Data("not json".utf8)) == nil)
        #expect(InboxImporter.parse(Data()) == nil)
        #expect(InboxImporter.parse(Data("[]".utf8)) == nil)
        #expect(InboxImporter.parse(Data("null".utf8)) == nil)
    }

    @Test("a reason of the wrong type is refused rather than coerced")
    func refusesWrongTypes() {
        #expect(parse(["intent": 42]) == nil)
        #expect(parse(["intent": ["nested"]]) == nil)
    }

    @Test("an unusable image is dropped but the reason is kept")
    func survivesABadImage() throws {
        let item = try #require(parse([
            "intent": "still worth keeping",
            "imageBase64": "!!!! not base64 !!!!",
        ]))

        #expect(item.imageData == nil)
        #expect(item.intent == "still worth keeping")
    }

    /// Otherwise an item with no stated time lands in 1970 and sorts to the
    /// bottom of the library, where it is never seen again.
    @Test("a missing or unreadable time falls back rather than landing in 1970")
    func fallsBackForTheDate() throws {
        let now = Date(timeIntervalSince1970: 1_757_289_600)

        #expect(try #require(parse(["intent": "no date"], now: now)).createdAt == now)
        #expect(try #require(parse(["intent": "bad date", "createdAt": "yesterday"], now: now)).createdAt == now)
    }

    @Test("dates parse with or without fractional seconds")
    func acceptsBothStampFormats() throws {
        let plain = try #require(parse(["intent": "a", "createdAt": "2026-09-07T14:30:00Z"]))
        let fractional = try #require(parse(["intent": "b", "createdAt": "2026-09-07T14:30:00.250Z"]))

        #expect(abs(plain.createdAt.timeIntervalSince(fractional.createdAt)) < 1)
    }

    @Test("an unstated source is attributed to the phone, not to nothing")
    func defaultsTheSource() throws {
        #expect(try #require(parse(["intent": "a"])).source == "iPhone")
        #expect(try #require(parse(["intent": "a", "source": "  "])).source == "iPhone")
        #expect(try #require(parse(["intent": "a", "source": "iPad"])).source == "iPad")
    }

    @Test("unknown fields a later Shortcut adds are ignored")
    func toleratesUnknownFields() throws {
        let item = try #require(parse([
            "intent": "forward compatible",
            "location": ["lat": 1.0, "lon": 2.0],
            "version": 9,
        ]))

        #expect(item.intent == "forward compatible")
    }

    /// `#engram` has to mean the same thing whichever device it was typed on.
    @Test("hashtags typed on the phone become topics, as they do on the Mac")
    func splitsHashtagsLikeTheMacDoes() {
        let record = InboxImporter.makeRecord(from: InboxItem(
            intent: "revisit this #engram #retrieval",
            imageData: nil,
            createdAt: Date(),
            source: "iPhone"
        ))

        #expect(record.topics == ["engram", "retrieval"])
        #expect(record.intent == "revisit this")
    }

    @Test("the phone is recorded as the provenance")
    func recordsProvenance() {
        let record = InboxImporter.makeRecord(from: InboxItem(
            intent: "from my phone",
            imageData: nil,
            createdAt: Date(),
            source: "iPhone"
        ))

        #expect(record.sourceApp == "iPhone")
        #expect(record.provenanceLabel == "iPhone")
        // No window title, so "same window" scoring cannot match one phone
        // capture to another on the strength of both having none.
        #expect(record.windowTitle.isEmpty)
    }

    @Test("the time stated on the phone is kept, not the time of import")
    func keepsTheCaptureTime() {
        let captured = Date(timeIntervalSince1970: 1_757_289_600)
        let record = InboxImporter.makeRecord(from: InboxItem(
            intent: "captured earlier",
            imageData: nil,
            createdAt: captured,
            source: "iPhone"
        ))

        #expect(record.createdAt == captured)
    }
}

/// A reminder asked for on the phone is carried out on arrival, which means
/// nobody is watching when the sentence is read. Two of these failures would be
/// invisible rather than wrong-looking: a duration resolved against the wrong
/// clock is off by however long the Mac was asleep, and a reminder armed from a
/// date merely mentioned would fire for something the user never asked to be
/// reminded about. So the bar is pinned here rather than left to the parser.
@Suite("Reminders from a phone capture")
struct InboxReminderTests {
    /// Fixed zone, because quiet hours are whole hours in local time and the
    /// suite otherwise passes or fails depending on where it runs.
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func at(_ iso: String) -> Date {
        ISO8601DateFormatter().date(from: iso)!
    }

    private func item(_ intent: String, at createdAt: Date) -> InboxItem {
        InboxItem(intent: intent, imageData: nil, createdAt: createdAt, source: "iPhone")
    }

    /// The case this was built for, from a real capture.
    @Test("an explicit request with a stated duration is carried out")
    func armsAnExplicitRequest() throws {
        let captured = at("2026-09-08T20:06:00Z")
        let when = try #require(InboxImporter.reminderDate(
            for: item("Dinner for today, remind me to eat the same in 12 hours", at: captured),
            quietHours: QuietHours(),
            calendar: utc
        ))

        #expect(when == captured.addingTimeInterval(12 * 3600))
    }

    /// The one that would be invisible. This Mac may have been asleep for hours
    /// when the file landed, so resolving against the moment of import would
    /// silently slide every phone reminder later by however long that was.
    @Test("the duration counts from when it was said, not when it was imported")
    func anchorsToTheCaptureTime() throws {
        let captured = at("2026-09-08T20:06:00Z")
        let importedMuchLater = at("2026-09-08T23:30:00Z")

        let when = try #require(InboxImporter.reminderDate(
            for: item("remind me to eat in 12 hours", at: captured),
            quietHours: QuietHours(),
            calendar: utc
        ))

        #expect(when == captured.addingTimeInterval(12 * 3600))
        #expect(when != importedMuchLater.addingTimeInterval(12 * 3600))
    }

    /// At the Mac this is offered with the switch *off*, and there is nobody
    /// here to turn it on, so the honest equivalent is not setting it.
    @Test("a date merely mentioned does not arm anything")
    func ignoresADateWithNoRequest() {
        let when = InboxImporter.reminderDate(
            for: item("notes from tomorrow's standup", at: at("2026-09-08T14:00:00Z")),
            quietHours: QuietHours(),
            calendar: utc
        )

        #expect(when == nil)
    }

    /// `ReminderPhrase` falls back to tomorrow morning for a request that names
    /// no time, and that guess must not become a notification nobody confirmed.
    /// At the Mac the fallback is shown before it is armed; here it would not be.
    @Test("a request naming no time is not guessed at")
    func refusesToGuessAMissingTime() {
        let when = InboxImporter.reminderDate(
            for: item("remind me to look at this again", at: at("2026-09-08T14:00:00Z")),
            quietHours: QuietHours(),
            calendar: utc
        )

        #expect(when == nil)
    }

    /// The other app owns the do-not-disturb window, and a reminder arriving
    /// from a phone has no more licence to ignore it than one set at the Mac.
    @Test("a time inside quiet hours moves to the end of them")
    func defersPastQuietHours() throws {
        let captured = at("2026-09-08T14:00:00Z")
        let when = try #require(InboxImporter.reminderDate(
            for: item("remind me in 9 hours", at: captured),
            quietHours: QuietHours(isEnabled: true, startHour: 22, endHour: 7),
            calendar: utc
        ))

        // 23:00 is inside 22–07, so it lands at the first moment after.
        #expect(utc.component(.hour, from: when) == 7)
        #expect(when > captured.addingTimeInterval(9 * 3600))
    }

    /// A capture can sit in a syncing folder longer than the duration it names.
    /// The time is still recorded — it is what the user asked for, the library
    /// prints it as "already passed", and it still reaches the to-do app, which
    /// is the right place for something overdue.
    @Test("a capture that sat too long still records the time it asked for")
    func keepsATimeAlreadyGone() throws {
        let captured = Date().addingTimeInterval(-6 * 3600)
        let record = InboxImporter.makeRecord(
            from: item("remind me to check the oven in 1 hour", at: captured),
            quietHours: QuietHours()
        )

        let when = try #require(record.remindAt)
        #expect(when < Date())
        #expect(record.hasPendingReminder == false)
    }

    /// Nothing about an ordinary capture should acquire a reminder.
    @Test("a capture asking for nothing gets no reminder")
    func leavesAnOrdinaryCaptureAlone() {
        let record = InboxImporter.makeRecord(
            from: item("wiring diagram for the pedal", at: Date()),
            quietHours: QuietHours()
        )

        #expect(record.remindAt == nil)
    }
}

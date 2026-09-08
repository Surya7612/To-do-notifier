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

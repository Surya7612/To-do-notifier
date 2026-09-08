import Foundation
import Testing
@testable import TodoCompanion

/// Retrieval decides what the app volunteers unprompted, so its failure modes
/// are "nagged me about nothing" and "stayed quiet when it mattered". Scores
/// are asserted through observable behaviour — ordering, inclusion, and the
/// stated reason — rather than exact numbers, so the weights stay tunable.
@Suite("Contextual retrieval")
struct ContextRetrieverTests {
    @Test("a topic the user chose, visible on screen, surfaces the save")
    func matchesUserTopicOnScreen() throws {
        let saved = Fixture.saved(intent: "read this later", topics: ["engram"])
        let screen = Fixture.observation(text: "the engram paper on retrieval")

        let matches = ContextRetriever.related(to: screen, among: [saved])

        #expect(matches.count == 1)
        #expect(try #require(matches.first).reason.contains("#engram"))
    }

    @Test("the same window outranks merely the same app")
    func windowBeatsApp() throws {
        let sameWindow = Fixture.saved(intent: "one", app: "Xcode", window: "Brain.swift")
        let sameApp = Fixture.saved(intent: "two", app: "Xcode", window: "Other.swift")
        let screen = Fixture.observation(app: "Xcode", window: "Brain.swift")

        let matches = ContextRetriever.related(to: screen, among: [sameApp, sameWindow])

        #expect(matches.count == 2)
        #expect(try #require(matches.first).context.intent == "one")
        #expect(try #require(matches.first).reason.contains("same window"))
    }

    @Test("a save with nothing in common is dropped")
    func unrelatedSaveIsDropped() {
        let saved = Fixture.saved(intent: "renew passport", app: "Safari", window: "Passport renewal")
        let screen = Fixture.observation(text: "func cropped(to selection:", app: "Xcode", window: "Brain.swift")

        #expect(ContextRetriever.related(to: screen, among: [saved]).isEmpty)
    }

    @Test("words shared between the saved reason and the screen count as a match")
    func intentOverlapMatches() throws {
        let saved = Fixture.saved(intent: "figure out retrieval scoring later")
        let screen = Fixture.observation(text: "retrieval scoring threshold tuning")

        let matches = ContextRetriever.related(to: screen, among: [saved])

        #expect(matches.count == 1)
        #expect(try #require(matches.first).reason.contains("mentions"))
    }

    @Test("a single shared word is too weak to surface a save")
    func oneSharedWordIsNotEnough() {
        let saved = Fixture.saved(intent: "look into retrieval sometime")
        let screen = Fixture.observation(text: "retrieval")

        #expect(ContextRetriever.related(to: screen, among: [saved]).isEmpty)
    }

    @Test("common words alone are not a match")
    func stopwordsDoNotMatch() {
        // Every word here is either a stopword or too short to count. Without
        // that filter, any two pieces of English text look related.
        let saved = Fixture.saved(intent: "the app and the window with this code")
        let screen = Fixture.observation(text: "the file and the app with that code")

        #expect(ContextRetriever.related(to: screen, among: [saved]).isEmpty)
    }

    @Test("recency breaks ties but cannot promote an irrelevant save")
    func recencyOnlyBreaksTies() throws {
        let fresh = Fixture.saved(intent: "fresh", app: "Xcode", daysOld: 0)
        let stale = Fixture.saved(intent: "stale", app: "Xcode", daysOld: 200)
        let screen = Fixture.observation(app: "Xcode")

        let matches = ContextRetriever.related(to: screen, among: [stale, fresh])

        #expect(try #require(matches.first).context.intent == "fresh")
    }

    @Test("at most three matches come back")
    func respectsLimit() {
        let saves = (0..<10).map { Fixture.saved(intent: "save \($0)", app: "Xcode", window: "Brain.swift") }
        let screen = Fixture.observation(app: "Xcode", window: "Brain.swift")

        #expect(ContextRetriever.related(to: screen, among: saves).count == 3)
    }

    /// Pins the rough edge the plan already calls out: being in the same app is
    /// worth 2.0 and the threshold is 2.0, so it squeaks through on its own.
    /// That is currently deliberate — it is the only signal available when
    /// nothing is on screen yet — but it means one busy editor can crowd out
    /// better matches. This test exists so raising the threshold is a visible
    /// decision rather than a silent behaviour change.
    @Test("being in the same app is, on its own, just enough to surface a save")
    func sameAppAloneClearsTheThreshold() {
        let saved = Fixture.saved(intent: "unrelated entirely", app: "Xcode")
        let screen = Fixture.observation(app: "Xcode")

        #expect(ContextRetriever.related(to: screen, among: [saved]).count == 1)
    }

    @Test("every match explains itself")
    func everyMatchHasAReason() {
        let saves = [
            Fixture.saved(intent: "topic", topics: ["engram"]),
            Fixture.saved(intent: "window", app: "Xcode", window: "Brain.swift"),
        ]
        let screen = Fixture.observation(text: "engram", app: "Xcode", window: "Brain.swift")

        let matches = ContextRetriever.related(to: screen, among: saves)

        #expect(!matches.isEmpty)
        #expect(matches.allSatisfy { !$0.reason.isEmpty })
    }

    @Test("prompt lines quote the user's reason verbatim")
    func promptLinesPreserveIntent() throws {
        let saved = Fixture.saved(intent: "I wanted to compare this to Engram", topics: ["engram"])
        let screen = Fixture.observation(text: "engram")

        let lines = ContextRetriever.promptLines(for: ContextRetriever.related(to: screen, among: [saved]))

        #expect(lines.count == 1)
        // The model must see the user's own words, not a paraphrase of them.
        #expect(try #require(lines.first).contains("I wanted to compare this to Engram"))
    }

    @Test("no candidates means no matches")
    func emptyCandidatesAreSafe() {
        #expect(ContextRetriever.related(to: Fixture.observation(text: "anything"), among: []).isEmpty)
        #expect(ContextRetriever.promptLines(for: []).isEmpty)
    }
}

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

    @Test("a save in the project the user says they are working on is favoured")
    func activeProjectIsFavoured() throws {
        let project = Project(name: "Engram")
        let inProject = Fixture.saved(intent: "unrelated wording entirely")
        inProject.project = project
        let sameApp = Fixture.saved(intent: "something else", app: "Xcode")
        let screen = Fixture.observation(app: "Xcode")

        let matches = ContextRetriever.related(to: screen,
                                               among: [sameApp, inProject],
                                               inProject: project)

        #expect(try #require(matches.first).context.intent == "unrelated wording entirely")
        #expect(try #require(matches.first).reason.contains("Engram"))
    }

    @Test("belonging to a different project is not a match")
    func otherProjectsAreNotFavoured() {
        let active = Project(name: "Engram")
        let other = Project(name: "Taxes")
        let saved = Fixture.saved(intent: "nothing in common")
        saved.project = other

        let matches = ContextRetriever.related(to: Fixture.observation(text: "unrelated screen"),
                                               among: [saved],
                                               inProject: active)

        #expect(matches.isEmpty)
    }

    @Test("with no project chosen, project membership changes nothing")
    func noActiveProjectIsNeutral() {
        let saved = Fixture.saved(intent: "nothing in common")
        saved.project = Project(name: "Engram")

        #expect(ContextRetriever.related(to: Fixture.observation(text: "unrelated screen"),
                                         among: [saved]).isEmpty)
    }

    @Test("no candidates means no matches")
    func emptyCandidatesAreSafe() {
        #expect(ContextRetriever.related(to: Fixture.observation(text: "anything"), among: []).isEmpty)
        #expect(ContextRetriever.promptLines(for: []).isEmpty)
    }
}

/// Meaning-based matching is allowed here only on the condition that it can
/// explain itself and can only ever add. These tests are the condition: they
/// use hand-built vectors rather than a running model, so they check the
/// integration rather than the quality of anyone's embeddings.
@Suite("Retrieval by meaning")
struct SemanticRetrievalTests {
    /// A vector pointing almost exactly along `axis`, so similarity to another
    /// unit axis vector is controllable without a model.
    private func vector(axis: Int, of count: Int = 8, weight: Float = 1) -> Embedding {
        var values = [Float](repeating: 0.001, count: count)
        values[axis] = weight
        return Embedding(values)!
    }

    private func saved(intent: String, embedding: Embedding?, model: String = "test-model") -> SavedContext {
        let context = Fixture.saved(intent: intent)
        if let embedding {
            context.embeddingData = embedding.data
            context.embeddingModel = model
        }
        return context
    }

    @Test("a save worded nothing like the screen still surfaces, and says why")
    func meaningAloneCanSurfaceASave() throws {
        let close = vector(axis: 0)
        // Shares no words at all with the screen text, so every literal signal
        // scores zero and only meaning can carry it over the threshold.
        let context = saved(intent: "display grabbing notes", embedding: close)
        let screen = Fixture.observation(text: "unrelated wording entirely")

        let matches = ContextRetriever.related(to: screen,
                                               among: [context],
                                               screenEmbedding: close)

        #expect(matches.count == 1)
        #expect(try #require(matches.first).reason.contains("close in meaning"))
    }

    @Test("an unrelated vector does not surface anything")
    func distantMeaningStaysQuiet() {
        let context = saved(intent: "renew passport", embedding: vector(axis: 0))
        let screen = Fixture.observation(text: "completely different subject")

        #expect(ContextRetriever.related(to: screen,
                                         among: [context],
                                         screenEmbedding: vector(axis: 4)).isEmpty)
    }

    /// The feature is opt-in, so with no query vector the behaviour has to be
    /// exactly what it was before embeddings existed.
    @Test("with the feature off, scoring is unchanged")
    func absentQueryVectorChangesNothing() {
        let context = saved(intent: "display grabbing notes", embedding: vector(axis: 0))
        let screen = Fixture.observation(text: "unrelated wording entirely")

        #expect(ContextRetriever.related(to: screen, among: [context]).isEmpty)
    }

    @Test("a save with no vector of its own is simply scored without one")
    func missingCandidateVectorIsNotAnError() throws {
        let unvectored = saved(intent: "engram retrieval", embedding: nil, model: "")
        let screen = Fixture.observation(text: "engram retrieval scoring")

        let matches = ContextRetriever.related(to: screen,
                                               among: [unvectored],
                                               screenEmbedding: vector(axis: 0))

        #expect(matches.count == 1)
        let match = try #require(matches.first)
        #expect(!match.reason.contains("close in meaning"))
    }

    /// Meaning is additive. A save that already matched on words must not lose
    /// its literal reason, or the explanation would get worse as the app got
    /// cleverer.
    @Test("a literal match keeps its own reason when meaning also agrees")
    func meaningAddsToReasonsRatherThanReplacingThem() throws {
        let close = vector(axis: 0)
        let context = saved(intent: "engram retrieval scoring", embedding: close)
        let screen = Fixture.observation(text: "engram retrieval scoring", app: "Xcode")

        let match = try #require(ContextRetriever.related(to: screen,
                                                          among: [context],
                                                          screenEmbedding: close).first)

        #expect(match.reason.contains("mentions"))
        #expect(match.reason.contains("close in meaning"))
    }

    @Test("a stronger resemblance is worth more than a marginal one")
    func scoreScalesWithSimilarity() throws {
        let query = vector(axis: 0)
        let strong = try #require(ContextRetriever.meaningScore(vector(axis: 0), query))
        let marginal = try #require(ContextRetriever.meaningScore(
            Embedding([0.6, 0.8, 0, 0, 0, 0, 0, 0])!, query
        ))

        #expect(strong > marginal)
        #expect(strong <= ContextRetriever.similarityWeight)
    }

    /// Below the floor it must be nil rather than zero: a score of zero would
    /// still append the "close in meaning" reason to a match that is not.
    @Test("similarity below the floor contributes nothing at all")
    func belowFloorIsNilNotZero() {
        let query = vector(axis: 0)
        let across = Embedding([0, 1, 0, 0, 0, 0, 0, 0])!

        #expect(ContextRetriever.meaningScore(across, query) == nil)
    }

    @Test("a shared window still outranks a resemblance")
    func statedFactsOutrankResemblance() throws {
        let close = vector(axis: 0)
        let resembles = saved(intent: "worded differently", embedding: close)
        let sameWindow = saved(intent: "same place", embedding: nil, model: "")
        sameWindow.sourceApp = "Xcode"
        sameWindow.windowTitle = "Brain.swift"

        let screen = Fixture.observation(app: "Xcode", window: "Brain.swift")
        let matches = ContextRetriever.related(to: screen,
                                               among: [resembles, sameWindow],
                                               screenEmbedding: close)

        #expect(try #require(matches.first).context.intent == "same place")
    }

    @Test("library search by meaning ranks by similarity and explains itself")
    func librarySearchRanksAndExplains() throws {
        let query = vector(axis: 0)
        let exact = saved(intent: "closest", embedding: vector(axis: 0))
        let near = saved(intent: "nearby", embedding: Embedding([0.8, 0.6, 0, 0, 0, 0, 0, 0])!)
        let far = saved(intent: "unrelated", embedding: vector(axis: 5))

        let matches = ContextRetriever.matching(query, among: [far, near, exact])

        #expect(matches.map(\.context.intent) == ["closest", "nearby"])
        #expect(try #require(matches.first).reason == "close in meaning")
    }

    @Test("library search returns nothing when nothing resembles the query")
    func librarySearchCanComeBackEmpty() {
        let context = saved(intent: "unrelated", embedding: vector(axis: 5))

        #expect(ContextRetriever.matching(vector(axis: 0), among: [context]).isEmpty)
    }
}

/// What text a vector is computed from decides what meaning matching can find,
/// so the composition is a product decision rather than an implementation
/// detail.
@Suite("Embedding source")
struct EmbeddingSourceTests {
    @Test("the user's words, their topics, and the model's gloss are included")
    func combinesTheThingsWorthMatching() {
        let context = Fixture.saved(intent: "check this later", topics: ["engram"])
        context.aiSummary = "A page of ScreenCaptureKit documentation."

        let source = context.embeddingSource

        #expect(source.contains("check this later"))
        #expect(source.contains("#engram"))
        #expect(source.contains("ScreenCaptureKit"))
    }

    /// A page of interface furniture would swamp a one-sentence reason and make
    /// every save taken in the same app look alike. Literal search covers the
    /// screen text, and covers it better.
    @Test("raw screen text is deliberately left out")
    func excludesRecognizedText() {
        let context = Fixture.saved(intent: "keep this")
        context.recognizedText = "File Edit View Window Help Untitled Sidebar Inspector"

        #expect(!context.embeddingSource.contains("Inspector"))
    }

    @Test("a save with nothing to embed is not queued forever")
    func nothingToEmbedIsNotPending() {
        let empty = Fixture.saved(intent: "")

        #expect(empty.embeddingSource.isEmpty)
        #expect(empty.needsEmbedding(for: "nomic-embed-text") == false)
    }

    @Test("a save with no vector needs one")
    func missingVectorIsPending() {
        #expect(Fixture.saved(intent: "something").needsEmbedding(for: "nomic-embed-text"))
    }

    /// Vectors from two models are not comparable, so a model change has to
    /// invalidate rather than quietly mix two coordinate systems.
    @Test("changing the embedding model invalidates existing vectors")
    func modelChangeInvalidates() throws {
        let context = Fixture.saved(intent: "something")
        context.embeddingData = try #require(Embedding([1, 0, 0])).data
        context.embeddingModel = "nomic-embed-text"

        #expect(context.needsEmbedding(for: "nomic-embed-text") == false)
        #expect(context.needsEmbedding(for: "mxbai-embed-large"))
    }
}

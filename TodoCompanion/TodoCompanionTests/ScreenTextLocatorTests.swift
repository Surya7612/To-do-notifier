import CoreGraphics
import Testing

@testable import TodoCompanion

/// The locator decides whether the app draws a box on the user's screen, and
/// where. A wrong box is a confident claim about the wrong pixels, so most of
/// these pin the cases that must yield *nothing* rather than a best guess.
@Suite("Pointing at what an answer named")
struct ScreenTextLocatorTests {
    /// A menu bar comes back from Vision as one line of unrelated labels, which
    /// is the case the whole word-level design exists for.
    private func menuBar() -> [TextRegion] {
        let labels = ["Media", "Cut", "Edit", "Fusion", "Color", "Fairlight", "Deliver"]
        return labels.enumerated().map { position, label in
            TextRegion(
                string: label,
                boundingBox: CGRect(x: 0.1 + Double(position) * 0.1, y: 0.02, width: 0.08, height: 0.03),
                line: 0,
                position: position
            )
        }
    }

    @Test("a quoted label is found")
    func quotedLabelMatches() throws {
        let match = try #require(
            ScreenTextLocator.locate(named: "Click the \"Color\" page at the bottom.", in: menuBar())
        )

        #expect(match.text == "Color")
    }

    @Test("curly quotes and backticks count too, since models emit both")
    func alternateQuotingMatches() throws {
        let curly = try #require(ScreenTextLocator.locate(named: "Open \u{201C}Fusion\u{201D} now.", in: menuBar()))
        #expect(curly.text == "Fusion")

        let backticks = try #require(ScreenTextLocator.locate(named: "Open `Fusion` now.", in: menuBar()))
        #expect(backticks.text == "Fusion")
    }

    @Test("a short unquoted word is not believed")
    func shortUnquotedWordIsIgnored() {
        // "Cut" appears in the answer as an ordinary verb. Pointing at the Cut
        // page because the sentence used the word would be a wrong box, which is
        // worse than none.
        #expect(ScreenTextLocator.locate(named: "Now cut the clip in half.", in: menuBar()) == nil)
    }

    @Test("a long unquoted name is believed, because it cannot be ordinary prose")
    func longUnquotedNameMatches() throws {
        let match = try #require(ScreenTextLocator.locate(named: "Audio work happens in Fairlight.", in: menuBar()))

        #expect(match.text == "Fairlight")
    }

    @Test("an ordinary word long enough to clear the floor is still not believed")
    func longOrdinaryWordIsIgnored() {
        // The observed failure: Max replied "When should I remind you to record
        // the demo?" and offered to point at "should", which is six characters
        // and so cleared the length floor that was standing in for being a name.
        let regions = [
            TextRegion(string: "should", boundingBox: .init(x: 0.2, y: 0.4, width: 0.06, height: 0.02),
                       line: 4, position: 0),
        ]

        #expect(ScreenTextLocator.locate(named: "When should I remind you to record the demo?",
                                         in: regions) == nil)
    }

    @Test("a lowercase word is not offered, because prose is printed that way and labels are not")
    func lowercaseRunningTextIsIgnored() {
        // Gives up on a genuinely lowercase label, which is the cheaper mistake:
        // no box, rather than a confident one over unrelated running text.
        let regions = [
            TextRegion(string: "duration", boundingBox: .init(x: 0.2, y: 0.4, width: 0.08, height: 0.02),
                       line: 2, position: 0),
        ]

        #expect(ScreenTextLocator.locate(named: "Set the duration to four seconds.", in: regions) == nil)
    }

    @Test("an identifier still counts, since a digit or interior capital is never prose")
    func identifierMatches() throws {
        let regions = [
            TextRegion(string: "qwen3", boundingBox: .init(x: 0.2, y: 0.4, width: 0.05, height: 0.02),
                       line: 2, position: 0),
            TextRegion(string: "SwiftData", boundingBox: .init(x: 0.3, y: 0.4, width: 0.09, height: 0.02),
                       line: 2, position: 1),
        ]

        let match = try #require(ScreenTextLocator.locate(named: "The SwiftData store holds it.", in: regions))
        #expect(match.text == "SwiftData")
    }

    @Test("quoting still wins, even for a word that would otherwise be refused")
    func quotingOverridesTheLabelShape() throws {
        // Max quoting a label character for character is Max stating what it
        // meant, which outranks every inference this file makes.
        let regions = [
            TextRegion(string: "should", boundingBox: .init(x: 0.2, y: 0.4, width: 0.06, height: 0.02),
                       line: 4, position: 0),
        ]

        let match = try #require(ScreenTextLocator.locate(named: "The word \"should\" on line four.",
                                                          in: regions))
        #expect(match.text == "should")
    }

    @Test("a match inside a longer word does not count")
    func respectsWordBoundaries() {
        let regions = [TextRegion(string: "Color", boundingBox: .init(x: 0, y: 0, width: 0.1, height: 0.1),
                                  line: 0, position: 0)]

        #expect(ScreenTextLocator.locate(named: "Adjust the \"colorimetry\" readout.", in: regions) == nil)
    }

    @Test("the longer label wins, being the more specific claim")
    func prefersTheLongerPhrase() throws {
        let regions = [
            TextRegion(string: "Color", boundingBox: .init(x: 0.1, y: 0.5, width: 0.05, height: 0.02),
                       line: 3, position: 0),
            TextRegion(string: "Wheels", boundingBox: .init(x: 0.16, y: 0.5, width: 0.06, height: 0.02),
                       line: 3, position: 1),
        ]

        let match = try #require(ScreenTextLocator.locate(named: "Use the \"Color Wheels\" panel.", in: regions))

        #expect(match.text == "Color Wheels")
        // The box has to cover both words, or it points at half the control.
        #expect(match.boundingBox.width > 0.1)
    }

    @Test("words Max uses to describe controls are never the target")
    func descriptiveWordsAreIneligible() {
        let regions = [
            TextRegion(string: "Settings", boundingBox: .init(x: 0, y: 0, width: 0.1, height: 0.05),
                       line: 0, position: 0),
        ]

        // Long enough to clear the length floor, and still the wrong thing to
        // point at: Max is describing a kind of thing, not naming this one.
        #expect(ScreenTextLocator.locate(named: "Open the settings for that.", in: regions) == nil)
    }

    @Test("a quoted label that is not on screen finds nothing")
    func absentLabelFindsNothing() {
        #expect(ScreenTextLocator.locate(named: "Press \"Render\" to finish.", in: menuBar()) == nil)
    }

    @Test("no recognized text means no guess")
    func emptyScreenFindsNothing() {
        #expect(ScreenTextLocator.locate(named: "Click \"Color\".", in: []) == nil)
    }

    @Test("words from different lines are never combined into one label")
    func doesNotSpanLines() {
        let regions = [
            TextRegion(string: "Color", boundingBox: .init(x: 0.1, y: 0.9, width: 0.05, height: 0.02),
                       line: 0, position: 0),
            TextRegion(string: "Wheels", boundingBox: .init(x: 0.8, y: 0.1, width: 0.06, height: 0.02),
                       line: 7, position: 0),
        ]

        let match = ScreenTextLocator.locate(named: "Use \"Color Wheels\".", in: regions)

        // A box spanning both would cover most of the screen. Either single word
        // is a defensible target; the pair is not.
        #expect(match?.text != "Color Wheels")
    }
}

/// Follow-along draws while an answer is being read aloud, so unlike the button
/// it cannot show the user its match first and wait to be told to go ahead.
/// What replaces that consent is this: only a label Max put in double quotes can
/// ever be boxed. Quoting is Max stating which words it meant, so nothing
/// inferred from prose reaches the screen — which is the standing rule, kept
/// rather than relaxed.
@Suite("Pointing along with the voice")
struct FollowAlongMatchingTests {
    private func menuBar() -> [TextRegion] {
        ["Media", "Fusion", "Color", "Fairlight"].enumerated().map { position, label in
            TextRegion(
                string: label,
                boundingBox: CGRect(x: 0.1 + Double(position) * 0.1, y: 0.02, width: 0.08, height: 0.03),
                line: 0,
                position: position
            )
        }
    }

    @Test("a quoted label is still found")
    func quotedLabelMatches() throws {
        let match = try #require(
            ScreenTextLocator.locate(named: "Open the \"Color\" page.",
                                     in: menuBar(),
                                     requiringQuoted: true)
        )

        #expect(match.text == "Color")
    }

    /// The whole point of the flag. "Fairlight" is believed by the button,
    /// because it is long and printed like a name, and that is still an
    /// inference — fine when the user is shown it on a button beforehand, not
    /// fine when it draws on the screen unannounced.
    @Test("an unquoted name the button would believe is refused here")
    func unquotedNameIsRefused() throws {
        let clause = "Audio work happens in Fairlight."

        // Believed on the button's terms.
        #expect(try #require(ScreenTextLocator.locate(named: clause, in: menuBar())).text == "Fairlight")

        // And refused on these.
        #expect(ScreenTextLocator.locate(named: clause, in: menuBar(), requiringQuoted: true) == nil)
    }

    /// Most clauses of most answers quote nothing at all, so this is the common
    /// case rather than an edge: the box stays where it was and the sentence
    /// goes by without anything being drawn.
    @Test("a clause quoting nothing matches nothing")
    func unquotedClauseMatchesNothing() {
        #expect(ScreenTextLocator.locate(named: "That should take about a minute.",
                                         in: menuBar(),
                                         requiringQuoted: true) == nil)
    }

    @Test("a quoted label that is not on screen is still not drawn")
    func absentQuotedLabelMatchesNothing() {
        #expect(ScreenTextLocator.locate(named: "Press \"Render\" now.",
                                         in: menuBar(),
                                         requiringQuoted: true) == nil)
    }

    /// The button's behaviour has to be byte-for-byte what it was, since this
    /// added a parameter to the function it depends on.
    @Test("the default is unchanged, so the button still believes a long name")
    func defaultIsUnchanged() throws {
        let match = try #require(ScreenTextLocator.locate(named: "Audio lives in Fairlight.",
                                                          in: menuBar()))

        #expect(match.text == "Fairlight")
    }

    @Test("a lesson quote with trailing punctuation still finds the on-screen label")
    func punctuationStrippedLabelMatches() throws {
        let match = try #require(
            ScreenTextLocator.locate(label: "Fairlight:", in: menuBar())
        )
        #expect(match.text == "Fairlight")
    }

    @Test("a spaced quote matches a collapsed on-screen identifier")
    func collapsedIdentifierMatches() throws {
        let regions = [
            TextRegion(string: "fooBar",
                       boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.2, height: 0.05),
                       line: 0,
                       position: 0),
        ]
        let match = try #require(ScreenTextLocator.locate(label: "foo Bar", in: regions))
        #expect(match.text == "fooBar")
    }
}

/// Vision normalizes from the bottom left and so does AppKit's screen space, so
/// this mapping needs no flip — where `cropped(to:)` does, because it targets a
/// `CGImage`. Getting that wrong puts the box a mirrored distance up the screen,
/// which looks plausible and is wrong, so it is pinned.
@Suite("Placing a normalized box on screen")
struct ScreenRectTests {
    private let display = CGRect(x: 0, y: 0, width: 1000, height: 800)

    @Test("a box maps to the matching fraction of the display")
    func mapsProportionally() {
        let rect = ScreenTextLocator.screenRect(
            for: CGRect(x: 0.25, y: 0.5, width: 0.1, height: 0.05),
            in: display
        )

        #expect(rect == CGRect(x: 250, y: 400, width: 100, height: 40))
    }

    @Test("vertical position is not flipped")
    func doesNotFlipVertically() {
        // Near the top in Vision's terms must land near the top in AppKit's,
        // which for a 0-origin display means a high y.
        let rect = ScreenTextLocator.screenRect(
            for: CGRect(x: 0, y: 0.95, width: 0.1, height: 0.02),
            in: display
        )

        #expect(rect.minY > 700)
    }

    @Test("a display with an offset origin carries it through")
    func respectsDisplayOrigin() {
        let secondary = CGRect(x: 1000, y: 300, width: 500, height: 400)
        let rect = ScreenTextLocator.screenRect(
            for: CGRect(x: 0.5, y: 0.5, width: 0.1, height: 0.1),
            in: secondary
        )

        #expect(rect.minX == 1250)
        #expect(rect.minY == 500)
    }

    /// After a crop the boxes are normalized against the selection, so the
    /// selection is what they map into. Using the whole display here would put
    /// every box in the wrong place by the crop's offset.
    @Test("a cropped capture maps into the selection, not the display")
    func mapsIntoTheSelection() {
        let selection = CGRect(x: 400, y: 200, width: 200, height: 100)
        let rect = ScreenTextLocator.screenRect(
            for: CGRect(x: 0, y: 0, width: 1, height: 1),
            in: selection
        )

        #expect(rect == selection)
    }
}

/// A lesson quotes labels that a page prints more than once, so which copy gets
/// the box has to be decided rather than left to whatever order a dictionary
/// happens to iterate in.
@Suite("Repeated labels")
struct RepeatedLabelTests {
    private func word(_ string: String, x: Double, y: Double, line: Int, position: Int = 0) -> TextRegion {
        TextRegion(string: string,
                   boundingBox: CGRect(x: x, y: y, width: 0.08, height: 0.02),
                   line: line, position: position)
    }

    @Test("every copy is offered, top of the screen first")
    func readingOrder() {
        // Line numbers deliberately disagree with position on screen.
        let regions = [
            word("get(1)", x: 0.1, y: 0.2, line: 0),
            word("get(1)", x: 0.1, y: 0.8, line: 5),
            word("get(1)", x: 0.6, y: 0.5, line: 2),
        ]
        let found = ScreenTextLocator.candidates(label: "get(1)", in: regions)
        #expect(found.map(\.boundingBox.minY) == [0.8, 0.5, 0.2])
        #expect(ScreenTextLocator.locate(label: "get(1)", in: regions)?.boundingBox.minY == 0.8)
    }

    @Test("the copy nearest the previous box wins")
    func nearestToPrevious() {
        let rects = [CGRect(x: 0, y: 700, width: 50, height: 10),
                     CGRect(x: 400, y: 200, width: 50, height: 10)]
        #expect(ScreenTextLocator.nearest(rects, to: CGPoint(x: 420, y: 210)) == rects[1])
        #expect(ScreenTextLocator.nearest(rects, to: nil) == rects[0])
    }

    @Test("a code quote is found inside the token that prints it")
    func insideCodeToken() throws {
        let regions = [word("lRUCache.get(1);", x: 0.1, y: 0.3, line: 0)]
        let match = try #require(ScreenTextLocator.locate(label: "get(1)", in: regions))
        #expect(match.text == "lRUCache.get(1);")
    }

    @Test("a plain word is never found inside a longer one")
    func notInsideAWord() {
        let regions = [word("target", x: 0.1, y: 0.3, line: 0),
                       word("forget(1)", x: 0.3, y: 0.3, line: 1)]
        #expect(ScreenTextLocator.locate(label: "get", in: regions) == nil)
        #expect(ScreenTextLocator.locate(label: "get(1)", in: regions) == nil)
    }

    @Test("a quote with a space is found across the words that print it")
    func acrossCodeWords() throws {
        // How LeetCode's LRU example reads to Vision: the call is split at its
        // space and glued to the receiver on the left.
        let regions = [word("lRUCache.put(1,", x: 0.1, y: 0.3, line: 0, position: 0),
                       word("1);", x: 0.2, y: 0.3, line: 0, position: 1),
                       word("//", x: 0.3, y: 0.3, line: 0, position: 2),
                       word("cache", x: 0.4, y: 0.3, line: 0, position: 3)]
        let found = ScreenTextLocator.candidates(label: "put(1, 1)", in: regions)
        #expect(found.map(\.text) == ["lRUCache.put(1, 1);"])
        #expect(ScreenTextLocator.locate(label: "put(1,1)", in: regions)?.text == "lRUCache.put(1, 1);")
    }

    @Test("an identifier is found inside the code that uses it")
    func identifierInsideCode() {
        let regions = [word("lRUCache.put(1,", x: 0.1, y: 0.3, line: 0)]
        #expect(ScreenTextLocator.locate(label: "LRUCache", in: regions) != nil)
        // An ordinary word still is not, however code-like its surroundings.
        #expect(ScreenTextLocator.locate(label: "cache", in: regions) == nil)
    }
}

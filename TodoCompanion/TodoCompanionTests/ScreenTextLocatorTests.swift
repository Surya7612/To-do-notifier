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

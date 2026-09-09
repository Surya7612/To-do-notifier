import Foundation
import Testing
@testable import TodoCompanion

@Suite("TabChordDetector")
struct TabChordDetectorTests {
    @Test func tabThenQFiresOnce() {
        var detector = TabChordDetector()
        #expect(detector.keyDown(code: 48, isRepeat: false) == false) // Tab
        #expect(detector.keyDown(code: 12, isRepeat: false) == true)  // Q
    }

    @Test func qAloneDoesNotFire() {
        var detector = TabChordDetector()
        #expect(detector.keyDown(code: 12, isRepeat: false) == false)
    }

    @Test func keyRepeatDoesNotRefire() {
        var detector = TabChordDetector()
        _ = detector.keyDown(code: 48, isRepeat: false)
        #expect(detector.keyDown(code: 12, isRepeat: false) == true)
        #expect(detector.keyDown(code: 12, isRepeat: true) == false)
    }

    @Test func releasingTabCancelsTheChord() {
        var detector = TabChordDetector()
        _ = detector.keyDown(code: 48, isRepeat: false)
        detector.keyUp(code: 48)
        #expect(detector.keyDown(code: 12, isRepeat: false) == false)
    }
}

@Suite("AXControlLocator ranking")
struct AXControlLocatorTests {
    @Test func exactMatchOutranksContains() {
        #expect(AXControlLocator.rank(candidate: "Save", against: "Save") == .exact)
        // Whole-word title match is exact — AX often puts the verb in a longer title.
        #expect(AXControlLocator.rank(candidate: "Save Document", against: "Save") == .exact)
        #expect(AXControlLocator.rank(candidate: "Autosave", against: "Save") == .contains)
        #expect(AXControlLocator.rank(candidate: "Cancel", against: "Save") == .none)
    }

    @Test func shortNeedleInsideLongerWordIsRefused() {
        // "ok" inside "book" would be a bad AX match for a button named OK.
        #expect(AXControlLocator.rank(candidate: "BOOK", against: "OK") == .none)
    }

    @Test func attributesPickTheBestRank() {
        let rank = AXControlLocator.rank(
            attributes: ["toolbar", "Save", "button"],
            against: "Save"
        )
        #expect(rank == .exact)
    }

    @Test func emptyTargetNeverMatches() {
        #expect(AXControlLocator.rank(candidate: "Save", against: "  ") == .none)
        #expect(AXControlLocator.rank(attributes: ["Save"], against: "") == .none)
    }
}

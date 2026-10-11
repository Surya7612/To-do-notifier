import Foundation
import Testing
@testable import TodoCompanion

/// The one place the app reports on whether its own resurfacing helps, so it
/// must not flatter itself: a keep never shown is not counted, and uses can
/// never exceed showings.
@Suite("Resurfacing usefulness")
struct ResurfaceStatsTests {
    @Test("keeps never shown are left out of the totals")
    func ignoresUnshown() {
        let counts = ResurfaceStats.counts([(shown: 0, used: 0), (shown: 3, used: 1), (shown: 2, used: 0)])
        #expect(counts == .init(keepsShown: 2, timesShown: 5, timesUsed: 1))
    }

    @Test("uses are capped at showings")
    func capsUses() {
        let counts = ResurfaceStats.counts([(shown: 1, used: 4)])
        #expect(counts.timesUsed == 1)
    }

    @Test("nothing is said before anything was shown")
    func silentWhenEmpty() {
        #expect(ResurfaceStats.summary(.init()) == nil)
        #expect(ResurfaceStats.detail(shown: 0, used: 0) == nil)
    }

    @Test("a summary that found no use says so plainly")
    func admitsNoUse() throws {
        let line = try #require(ResurfaceStats.summary(.init(keepsShown: 3, timesShown: 7, timesUsed: 0)))
        #expect(line.contains("3 keeps"))
        #expect(line.contains("7 times"))
        #expect(line.contains("not opened any"))
    }

    @Test("the per-keep line counts both sides")
    func detailLine() {
        #expect(ResurfaceStats.detail(shown: 4, used: 2) == "Brought back 4 times · opened 2 times")
        #expect(ResurfaceStats.detail(shown: 1, used: 0) == "Brought back once · not opened from there yet")
    }
}

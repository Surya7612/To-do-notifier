import Foundation
import Testing
@testable import TodoCompanion

@Suite("Pacing the pen against the narration")
struct SketchTimelineTests {
    private let car = BoardScene.Shape.icon(id: "car", x: 0.1, y: 0.4, w: 0.2, h: 0.2,
                                            pictogram: .car, color: .primary, label: nil)
    private let bay = BoardScene.Shape.rect(id: "bay", x: 0.6, y: 0.4, w: 0.25, h: 0.18,
                                            color: .muted, label: "big: 1")
    private var link: BoardScene.Shape { .arrow(from: .id("car"), to: .id("bay"), color: .muted, label: nil) }

    @Test("things are drawn in the order the narration names them")
    func mentionOrderDecidesDrawingOrder() {
        let frame = BoardScene.Frame(step: 1, shapes: [car, bay])
        let reveals = SketchTimeline.reveals(for: frame, previous: nil,
                                             narration: "The big bay is free, so the car pulls in.")
        guard case let .draw(carStart, _) = reveals[0], case let .draw(bayStart, _) = reveals[1] else {
            Issue.record("both should draw"); return
        }
        #expect(bayStart < carStart)
    }

    @Test("an arrow is drawn after both of the things it joins")
    func arrowFollowsItsEnds() {
        let frame = BoardScene.Frame(step: 1, shapes: [link, car, bay])
        let reveals = SketchTimeline.reveals(for: frame, previous: nil, narration: "car then bay")
        guard case let .draw(arrowStart, _) = reveals[0],
              case let .draw(carStart, _) = reveals[1],
              case let .draw(bayStart, _) = reveals[2] else {
            Issue.record("all should draw"); return
        }
        #expect(arrowStart > carStart)
        #expect(arrowStart > bayStart)
    }

    @Test("what the previous cut drew is carried, and a changed label is rewritten only")
    func carryOverBetweenCuts() {
        let previous = BoardScene.Frame(step: 1, shapes: [car, bay])
        let relabelled = BoardScene.Shape.rect(id: "bay", x: 0.6, y: 0.4, w: 0.25, h: 0.18,
                                               color: .accent, label: "big: 0")
        let frame = BoardScene.Frame(step: 2, shapes: [car, relabelled, link])
        let reveals = SketchTimeline.reveals(for: frame, previous: previous, narration: nil)
        #expect(reveals[0] == .carried)
        if case .relabel = reveals[1] {} else { Issue.record("bay should be relabelled") }
        if case .draw = reveals[2] {} else { Issue.record("the new arrow should draw") }
    }

    @Test("a long narration slows the pen, but one box never crawls across it")
    func durationFollowsNarration() {
        let frame = BoardScene.Frame(step: 1, shapes: [car, bay, link])
        let quiet = SketchTimeline.duration(for: frame, previous: nil, narration: nil)
        let spoken = SketchTimeline.duration(
            for: frame, previous: nil,
            narration: String(repeating: "The car looks for a bay that fits. ", count: 4))
        #expect(spoken > quiet)

        let single = BoardScene.Frame(step: 1, shapes: [bay])
        let long = SketchTimeline.duration(for: single, previous: nil,
                                           narration: String(repeating: "word ", count: 80))
        #expect(long <= 1.6 + 0.001)
    }

    @Test("an unchanged frame does not redraw at all")
    func identicalFrameIsAllCarried() {
        let frame = BoardScene.Frame(step: 1, shapes: [car, bay, link])
        let reveals = SketchTimeline.reveals(for: frame, previous: frame, narration: "car bay")
        #expect(reveals.allSatisfy { $0 == .carried })
    }
}

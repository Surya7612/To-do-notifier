import Foundation
import Testing
@testable import TodoCompanion

@Suite("Reading a board scene out of an answer")
struct BoardSceneTests {
    private let sample = """
    Water is simple.

    1. Look at the oxygen in the middle.
    2. Two hydrogens attach at an angle.

    ```board
    {
      "title": "Making Water!",
      "frames": [
        {
          "step": 1,
          "shapes": [
            { "type": "circle", "id": "o", "x": 0.5, "y": 0.45, "r": 0.12, "color": "oxygen", "label": "O" },
            { "type": "text", "x": 0.5, "y": 0.12, "text": "One oxygen atom", "color": "emphasis" }
          ]
        },
        {
          "step": 2,
          "shapes": [
            { "type": "circle", "id": "o", "x": 0.5, "y": 0.45, "r": 0.12, "color": "oxygen", "label": "O" },
            { "type": "circle", "id": "h1", "x": 0.32, "y": 0.28, "r": 0.08, "color": "hydrogen", "label": "H" },
            { "type": "arrow", "from": "h1", "to": "o", "color": "muted" },
            { "type": "text", "x": 0.5, "y": 0.88, "text": "Two hydrogens bond to oxygen", "color": "emphasis" }
          ]
        }
      ]
    }
    ```
    """

    @Test("a closed board fence becomes a scene with its frames")
    func closedFenceBecomesAScene() throws {
        let scene = try #require(BoardScene.from(answer: sample))

        #expect(scene.title == "Making Water!")
        #expect(scene.frames.count == 2)
        #expect(scene.frames[0].step == 1)
        #expect(scene.frames[1].shapes.count == 4)
        #expect(scene.isStoryboard)
        #expect(BoardScene.storyboard(from: sample) != nil)
    }

    @Test("a sparse single-frame board is not a storyboard; a dense one is")
    func singleFrameStoryboardThreshold() {
        let sparse = """
        ```board
        { "title": "Poster", "frames": [ { "step": 1, "shapes": [
          { "type": "rect", "id": "a", "x": 0.2, "y": 0.3, "w": 0.3, "h": 0.2, "label": "only" }
        ] } ] }
        ```
        """
        #expect(BoardScene.from(answer: sparse)?.isStoryboard == false)
        #expect(BoardScene.storyboard(from: sparse) == nil)

        let dense = """
        ```board
        { "title": "Dense", "frames": [ { "step": 1, "shapes": [
          { "type": "rect", "id": "a", "x": 0.1, "y": 0.3, "w": 0.2, "h": 0.2, "label": "a" },
          { "type": "rect", "id": "b", "x": 0.4, "y": 0.3, "w": 0.2, "h": 0.2, "label": "b" },
          { "type": "arrow", "from": "a", "to": "b" },
          { "type": "text", "x": 0.5, "y": 0.1, "text": "tip" }
        ] } ] }
        ```
        """
        #expect(BoardScene.storyboard(from: dense) != nil)
    }

    @Test("sketch reveal timing grows with subjects and voice lead is shorter")
    func sketchTimingGrowsWithSubjects() {
        let short = SketchRevealTiming.durationSeconds(subjectCount: 1, linkCount: 0)
        let long = SketchRevealTiming.durationSeconds(subjectCount: 4, linkCount: 2)
        #expect(long > short)
        #expect(short >= 0.7)
        #expect(SketchRevealTiming.voiceLeadSeconds < short)
    }

    @Test("an array decodes with numeric values, pointers and highlights")
    func arrayDecodesLeniently() throws {
        let answer = """
        ```board
        { "frames": [ { "step": 1, "shapes": [
          { "type": "array", "id": "nums", "x": 0.1, "y": 0.4, "w": 0.8,
            "values": [2, 7, "11", 15.5, true], "highlight": [0, 9], "pointers": { "i": 0, "j": 1, "k": 40 } },
          { "type": "mark", "target": "nums", "style": "tick" },
          { "type": "path", "points": [[0.1, 0.9], [0.5, 0.7], [0.9, 0.8]], "label": "grows" },
          { "type": "rect", "id": "r", "x": 0.1, "y": 0.1, "w": 0.2, "h": 0.1, "label": 42 }
        ] } ] }
        ```
        """
        let frame = try #require(BoardScene.from(answer: answer)?.frames.first)
        guard case let .array(id, _, _, _, _, values, highlight, pointers, _, _) = frame.shapes[0] else {
            Issue.record("expected an array"); return
        }
        #expect(id == "nums")
        #expect(values == ["2", "7", "11", "15.5", "true"])
        // Out-of-range indexes are dropped rather than drawn off the end.
        #expect(highlight == [0])
        #expect(pointers.map(\.name) == ["i", "j"])
        #expect(frame.shapes[1] == .mark(target: "nums", style: .check, color: .accent))
        guard case let .path(points, _, label) = frame.shapes[2] else {
            Issue.record("expected a path"); return
        }
        #expect(points.count == 3)
        #expect(label == "grows")
        // A number where a string was expected costs nothing.
        guard case let .rect(_, _, _, _, _, _, rectLabel) = frame.shapes[3] else {
            Issue.record("expected a rect"); return
        }
        #expect(rectLabel == "42")
    }

    @Test("a check with coordinates and no target is the pictogram, not a mark")
    func checkWithoutTargetIsAnIcon() throws {
        let answer = """
        ```board
        { "frames": [ { "shapes": [ { "type": "check", "x": 0.4, "y": 0.4 } ] } ] }
        ```
        """
        let frame = try #require(BoardScene.from(answer: answer)?.frames.first)
        guard case let .icon(_, _, _, _, _, pictogram, _, _) = frame.shapes[0] else {
            Issue.record("expected an icon"); return
        }
        #expect(pictogram == .check)
    }

    @Test("a clean layout keeps the model's coordinates; an overlapping one is rebuilt")
    func cleanLayoutIsKept() throws {
        let tree = """
        ```board
        { "frames": [ { "shapes": [
          { "type": "circle", "id": "root", "x": 0.5, "y": 0.2, "r": 0.06, "label": "8" },
          { "type": "circle", "id": "l", "x": 0.3, "y": 0.5, "r": 0.06, "label": "3" },
          { "type": "circle", "id": "r", "x": 0.7, "y": 0.5, "r": 0.06, "label": "10" },
          { "type": "arrow", "from": "root", "to": "l" },
          { "type": "arrow", "from": "root", "to": "r" }
        ] } ] }
        ```
        """
        let frame = try #require(BoardScene.from(answer: tree)?.polishedForDisplay().frames.first)
        let ys: [Double] = frame.shapes.compactMap {
            if case let .circle(_, _, y, _, _, _) = $0 { return y }
            return nil
        }
        // A tree stays a tree rather than being flattened into one row.
        #expect(ys == [0.2, 0.5, 0.5])

        let overlapping = BoardScene.Frame(step: nil, shapes: [
            .rect(id: "a", x: 0.1, y: 0.1, w: 0.4, h: 0.3, color: .primary, label: "a"),
            .rect(id: "b", x: 0.15, y: 0.15, w: 0.4, h: 0.3, color: .primary, label: "b"),
        ])
        #expect(!BoardScene.hasCleanLayout(overlapping))
    }

    @Test("polish splits role/value, gaps boxes, and keeps arrows between them")
    func polishCleansWhiteboardFrames() throws {
        let messy = """
        ```board
        { "title": "Two Sum: remember earlier values for later",
          "frames": [ { "step": 2, "shapes": [
            { "type": "rect", "id": "a", "x": 0.05, "y": 0.2, "w": 0.4, "h": 0.3, "color": "accent",
              "label": "current: 7 at [index]" },
            { "type": "rect", "id": "b", "x": 0.1, "y": 0.25, "w": 0.35, "h": 0.28, "color": "primary",
              "label": "need: 9 - 7 = 2" },
            { "type": "rect", "id": "c", "x": 0.55, "y": 0.3, "w": 0.3, "h": 0.25, "color": "success",
              "label": "map: {2: 0}" },
            { "type": "text", "x": 0.5, "y": 0.1,
              "text": "A remembered partner gives the two indices when you find it", "color": "emphasis" }
          ] } ] }
        ```
        """
        let scene = try #require(BoardScene.from(answer: messy)?.polishedForDisplay())
        let frame = try #require(scene.frames.first)
        #expect(scene.title?.count ?? 0 <= 44)
        let boxes: [(x: Double, w: Double, label: String)] = frame.shapes.compactMap { shape in
            if case let .rect(_, x, _, w, _, _, label) = shape, let label {
                return (x, w, label)
            }
            return nil
        }
        #expect(boxes.count == 3)
        #expect(boxes.allSatisfy { $0.label.count <= 28 })
        #expect(!boxes.contains(where: { $0.label.contains("[index]") }))
        #expect(boxes.contains(where: { $0.label.contains("7") }))
        // Role captions sit above boxes so the value alone is not cryptic.
        let roles = frame.shapes.compactMap { shape -> String? in
            if case let .label(_, _, text, _) = shape { return text }
            return nil
        }
        #expect(roles.contains("current"))
        #expect(roles.contains("need"))
        // Neighbouring boxes must leave a gap — arrows attach to edges there.
        let sorted = boxes.sorted { $0.x < $1.x }
        for index in 0..<(sorted.count - 1) {
            #expect(sorted[index].x + sorted[index].w + 0.03 < sorted[index + 1].x)
        }
        #expect(frame.shapes.contains {
            if case .arrow = $0 { return true }
            return false
        })
    }

    @Test("icons and speech bubbles decode and survive polish")
    func iconsAndBubblesDecode() throws {
        let answer = """
        ```board
        { "title": "Parking lot map",
          "frames": [ { "step": 1, "shapes": [
            { "type": "bubble", "text": "Got a 2?", "x": 0.2, "y": 0.1, "w": 0.4, "h": 0.12 },
            { "type": "icon", "id": "c", "icon": "car", "x": 0.1, "y": 0.4, "w": 0.2, "h": 0.2, "label": "7" },
            { "type": "person", "id": "p", "x": 0.5, "y": 0.4, "w": 0.16, "h": 0.2, "label": "ask" },
            { "type": "arrow", "from": "c", "to": "p", "color": "muted" }
          ] } ] }
        ```
        """
        let scene = try #require(BoardScene.from(answer: answer)?.polishedForDisplay())
        let frame = try #require(scene.frames.first)
        #expect(frame.shapes.contains { if case .bubble = $0 { return true }; return false })
        #expect(frame.shapes.contains {
            if case let .icon(_, _, _, _, _, pictogram, _, _) = $0 { return pictogram == .car }
            return false
        })
        #expect(frame.shapes.contains {
            if case let .icon(_, _, _, _, _, pictogram, _, _) = $0 { return pictogram == .person }
            return false
        })
    }

    @Test("pictogram synonyms resolve")
    func pictogramSynonyms() {
        #expect(BoardPictogram.resolve("auto") == .car)
        #expect(BoardPictogram.resolve("human") == .person)
        #expect(BoardPictogram.resolve("bulb") == .lightbulb)
        #expect(BoardPictogram.resolve("cache") == .database)
        #expect(BoardPictogram.resolve("cog") == .gear)
        #expect(BoardPictogram.resolve("magnifier") == .search)
        #expect(BoardPictogram.resolve("spaceship") == nil)
    }

    @Test("system-design frames lay out in client / service / data tiers")
    func architectureLayoutUsesTiers() throws {
        let answer = """
        ```board
        { "title": "URL shortener",
          "frames": [ { "step": 1, "shapes": [
            { "type": "icon", "id": "web", "icon": "laptop", "x": 0.1, "y": 0.1, "w": 0.15, "h": 0.15, "label": "client" },
            { "type": "icon", "id": "api", "icon": "server", "x": 0.1, "y": 0.1, "w": 0.15, "h": 0.15, "label": "API" },
            { "type": "icon", "id": "db", "icon": "database", "x": 0.1, "y": 0.1, "w": 0.15, "h": 0.15, "label": "DB" },
            { "type": "arrow", "from": "web", "to": "api" },
            { "type": "arrow", "from": "api", "to": "db" },
            { "type": "text", "x": 0.5, "y": 0.05, "text": "Read path", "color": "emphasis" }
          ] } ] }
        ```
        """
        let frame = try #require(BoardScene.from(answer: answer)?.polishedForDisplay().frames.first)
        let icons: [(id: String, y: Double)] = frame.shapes.compactMap { shape in
            if case let .icon(id, _, y, _, _, _, _, _) = shape, let id {
                return (id, y)
            }
            return nil
        }
        let yWeb = try #require(icons.first { $0.id == "web" }?.y)
        let yAPI = try #require(icons.first { $0.id == "api" }?.y)
        let yDB = try #require(icons.first { $0.id == "db" }?.y)
        #expect(yWeb < yAPI)
        #expect(yAPI < yDB)
        #expect(frame.shapes.contains {
            if case let .label(_, _, text, _) = $0 { return text == "clients" || text == "services" || text == "data" }
            return false
        })
    }

    @Test("bad JSON is refused rather than inventing a diagram")
    func badJSONYieldsNothing() {
        let answer = """
        Hello.

        ```board
        { not json
        ```
        """
        #expect(BoardScene.from(answer: answer) == nil)
    }

    @Test("an unclosed board fence is refused while it is still arriving")
    func unclosedFenceYieldsNothing() {
        let answer = """
        Hello.

        ```board
        { "title": "WIP", "frames": [
        """
        #expect(BoardScene.from(answer: answer) == nil)
    }

    @Test("a fence that is not tagged board is ignored")
    func otherFencesAreIgnored() {
        let answer = """
        ```json
        { "title": "nope", "frames": [ { "shapes": [ { "type": "text", "x": 0.5, "y": 0.5, "text": "x" } ] } ] }
        ```
        """
        #expect(BoardScene.from(answer: answer) == nil)
    }

    @Test("lesson steps pick the matching frame")
    func lessonStepSelectsFrame() throws {
        let scene = try #require(BoardScene.from(answer: sample))

        #expect(scene.frameIndex(forLessonStep: 0) == 0)
        #expect(scene.frameIndex(forLessonStep: 1) == 1)
    }

    @Test("unknown colour tokens fall back to accent")
    func unknownColorFallsBack() {
        #expect(BoardScene.ColorToken.resolve("neon-slime") == .accent)
        #expect(BoardScene.ColorToken.resolve("oxygen") == .oxygen)
        #expect(BoardScene.ColorToken.resolve(nil) == .accent)
    }

    @Test("every concept colour token is named")
    func allConceptTokensExist() {
        for token in BoardScene.ColorToken.allCases {
            #expect(!token.rawValue.isEmpty)
        }
    }

    @Test("empty frames are refused")
    func emptyFramesYieldNothing() {
        let answer = """
        ```board
        { "title": "Empty", "frames": [] }
        ```
        """
        #expect(BoardScene.from(answer: answer) == nil)
    }
}

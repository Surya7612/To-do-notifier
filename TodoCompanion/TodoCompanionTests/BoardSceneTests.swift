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

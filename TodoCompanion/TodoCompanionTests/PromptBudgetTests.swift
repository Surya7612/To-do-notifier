import Foundation
import Testing
@testable import TodoCompanion

@MainActor
@Suite("What fits in a local model's window")
struct PromptBudgetTests {
    @Test func screenTextIsCutAtALineAndSaysSo() {
        let text = (1...200).map { "line \($0) of the editor" }.joined(separator: "\n")
        let clipped = Prompt.clipped(text, to: 500)

        #expect(clipped.count < text.count)
        #expect(clipped.hasSuffix("[Screen text continues; cut here to fit the model.]"))
        let body = clipped.components(separatedBy: "\n").dropLast()
        #expect(body.allSatisfy { $0.hasPrefix("line ") && $0.hasSuffix("of the editor") })
    }

    @Test func shortTextAndNoLimitAreLeftAlone() {
        #expect(Prompt.clipped("short", to: 500) == "short")
        #expect(Prompt.clipped(String(repeating: "x", count: 10_000), to: nil).count == 10_000)
    }

    @Test func onlyTheLocalLimitShortensTheUserMessage() {
        let screen = String(repeating: "let value = compute()\n", count: 1_000)
        let context = AskContext(observation: Fixture.observation(text: screen))

        let local = Prompt.user(question: "What is this?", context: context,
                                screenTextLimit: OllamaBrain.screenTextLimit)
        let hosted = Prompt.user(question: "What is this?", context: context)

        #expect(local.count < hosted.count)
        #expect(local.contains("cut here to fit the model"))
        #expect(!hosted.contains("cut here to fit the model"))
    }

    @Test func historyDropsTheBoardButKeepsTheLessonAndOtherCode() {
        let answer = """
        1. Look at "Run".
        ```swift
        print("hi")
        ```
        ```board
        {"frames": [{"shapes": []}]}
        ```
        2. Then "Stop".
        """
        let replayed = Prompt.withoutBoardFences(answer)

        #expect(!replayed.contains("frames"))
        #expect(replayed.contains("1. Look at \"Run\"."))
        #expect(replayed.contains("2. Then \"Stop\"."))
        #expect(replayed.contains("print(\"hi\")"))
        #expect(replayed.contains("```swift"))
    }

    @Test func anUnclosedBoardIsDroppedToTheEnd() {
        let replayed = Prompt.withoutBoardFences("Step one.\n```board\n{\"frames\": [")
        #expect(replayed == "Step one.")
    }
}

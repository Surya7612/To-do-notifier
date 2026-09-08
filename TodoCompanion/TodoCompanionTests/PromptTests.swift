import CoreGraphics
import Foundation
import Testing
@testable import TodoCompanion

/// The prompt is where this app's central rule lives: the user's own words
/// outrank the model's reading of the screen, and inference must never be
/// presented as something the user said. Those are product guarantees, so they
/// are worth pinning down.
@Suite("Prompt construction")
struct PromptTests {
    @Test("the active window is given as ground truth about which app is in use")
    func statesTheActiveWindow() {
        let context = AskContext(observation: Fixture.observation(app: "Xcode", window: "Brain.swift"))
        let prompt = Prompt.user(question: "what is this", context: context)

        #expect(prompt.contains("Active window: Xcode — Brain.swift"))
    }

    /// The model kept describing a screenshot open in an editor as though that
    /// were the running application. The fix was prompt wording, which means a
    /// regression here is invisible until someone notices bad answers.
    @Test("the system prompt separates the active app from what it is displaying")
    func distinguishesAppFromItsContents() {
        #expect(Prompt.system.contains("ground truth"))
        #expect(Prompt.system.contains("Never contradict it"))
        #expect(Prompt.system.lowercased().contains("screenshot"))
    }

    @Test("the user's saved notes are labelled as theirs and given precedence")
    func labelsMemoriesAsTheUsers() {
        let context = AskContext(observation: nil, memories: ["- \"compare this to Engram\""])
        let prompt = Prompt.user(question: "what now", context: context)

        #expect(prompt.contains("The user saved these earlier, in their own words:"))
        #expect(prompt.contains("compare this to Engram"))
        #expect(Prompt.system.contains("outrank"))
    }

    @Test("a chosen region is announced so the answer is about the selection")
    func announcesCroppedRegion() throws {
        var observation = Fixture.observation(image: Fixture.splitImage(width: 200, height: 200),
                                              app: "Safari")
        observation = try #require(observation.cropped(to: CGRect(x: 0, y: 50, width: 50, height: 50),
                                                       inDisplayFrame: CGRect(x: 0, y: 0, width: 100, height: 100)))

        let prompt = Prompt.user(question: "explain this", context: AskContext(observation: observation))

        #expect(prompt.contains("selected one region"))
    }

    @Test("an uncropped screen makes no claim about a region")
    func silentWhenNotCropped() {
        let prompt = Prompt.user(question: "explain this",
                                 context: AskContext(observation: Fixture.observation(app: "Safari")))

        #expect(!prompt.contains("selected one region"))
    }

    @Test("linked tasks are labelled as coming from the to-do app")
    func labelsLinkedTasks() {
        let context = AskContext(observation: nil, tasks: ["- Ship the test target"])
        let prompt = Prompt.user(question: "what should I do", context: context)

        #expect(prompt.contains("Open tasks from the user's to-do app:"))
    }

    @Test("screen text is sent when no image is attached")
    func fallsBackToScreenText() {
        let context = AskContext(observation: Fixture.observation(text: "some visible text"))
        let prompt = Prompt.user(question: "read it", context: context)

        #expect(prompt.contains("Text visible on screen:"))
        #expect(prompt.contains("some visible text"))
    }

    /// With a vision model the focused display goes as an image, but the other
    /// monitors still have to arrive as text or their context is lost.
    @Test("with an image attached, other monitors still come through as text")
    func secondaryDisplaysAccompanyTheImage() {
        let observation = Fixture.observation(
            text: "focused",
            others: [CapturedDisplay(image: Fixture.blankImage(), index: 2, recognizedText: "docs on monitor two")]
        )
        let prompt = Prompt.user(question: "help",
                                 context: AskContext(observation: observation, includeImage: true))

        #expect(prompt.contains("docs on monitor two"))
        #expect(!prompt.contains("Text visible on screen:"), "the image carries the focused display")
    }

    @Test("the question comes last")
    func questionIsLast() {
        let context = AskContext(observation: Fixture.observation(text: "context"),
                                 memories: ["- \"a note\""],
                                 tasks: ["- a task"])
        let prompt = Prompt.user(question: "the actual question", context: context)

        #expect(prompt.hasSuffix("Question: the actual question"))
    }

    @Test("a question with no screen at all still produces a usable prompt")
    func worksWithoutAnObservation() {
        let prompt = Prompt.user(question: "just asking", context: AskContext())

        #expect(prompt == "Question: just asking")
    }

    /// Whether an answer leaves the machine is shown in the panel, so these
    /// flags are user-facing claims about privacy rather than internal details.
    @Test("only the cloud brain reports that it leaves the machine")
    func brainsDeclareWhereAnswersGo() {
        let local = OllamaBrain(endpoint: URL(string: "http://127.0.0.1:11434")!, model: "llava")
        #expect(local.leavesTheMachine == false)
        #expect(OpenAIBrain(apiKey: "sk-not-used", model: "gpt-4o-mini").leavesTheMachine)
    }

    /// Asked to explain something not on screen, the local model opened with
    /// "The user's saved note about testing the microphone is unrelated to the
    /// current question. The note about testing the code is also unrelated." —
    /// two sentences of the model auditing its own context before answering.
    /// Saying notes are "background" was not enough; it had to be told not to
    /// narrate them.
    @Test("the model is told to answer rather than to review its context first")
    func forbidsNarratingIrrelevantContext() {
        #expect(Prompt.system.contains("Start with the answer"))
        #expect(Prompt.system.contains("is irrelevant"))
        #expect(Prompt.system.contains("do not restate the question"))
    }
}

/// The badge in the panel header states who will answer. It has to say
/// something different for each choice, or a provider switch looks like it did
/// nothing — which is exactly what happened when OpenAI was selected with no
/// key and the badge went on reading "Local".
@Suite("Answer destination")
struct AnswerDestinationTests {
    private func resolve(_ provider: AppSettings.Provider,
                         hasCloudKey: Bool,
                         cloudModel: String = "gpt-4o-mini") -> AppSettings.AnswerDestination {
        AppSettings.AnswerDestination.resolve(provider: provider,
                                              hasCloudKey: hasCloudKey,
                                              cloudModel: cloudModel)
    }

    @Test("the local choice is local whether or not a cloud key exists")
    func localIgnoresTheKey() {
        #expect(resolve(.ollama, hasCloudKey: false) == .local)
        #expect(resolve(.ollama, hasCloudKey: true) == .local)
    }

    @Test("choosing the cloud with a key names the model that will answer")
    func cloudNamesItsModel() {
        let destination = resolve(.openAI, hasCloudKey: true, cloudModel: "gpt-5")
        #expect(destination == .cloud("gpt-5"))
        #expect(destination.label == "gpt-5")
    }

    @Test("choosing the cloud with no key is its own state, not silently local")
    func missingKeyIsVisible() {
        let destination = resolve(.openAI, hasCloudKey: false)

        #expect(destination == .cloudWithoutKey)
        #expect(destination != .local, "the whole bug was this collapsing into .local")
        #expect(destination.label != AppSettings.AnswerDestination.local.label)
    }

    @Test("every choice produces a distinguishable label")
    func labelsAreDistinct() {
        let labels = [
            resolve(.ollama, hasCloudKey: false).label,
            resolve(.openAI, hasCloudKey: true).label,
            resolve(.openAI, hasCloudKey: false).label,
        ]
        #expect(Set(labels).count == labels.count)
    }

    /// The claim in the header must match what actually happens, so a selected
    /// cloud provider that cannot be used must not claim egress.
    @Test("only a usable cloud provider claims to leave the machine")
    func onlyUsableCloudLeaves() {
        #expect(resolve(.ollama, hasCloudKey: true).leavesTheMachine == false)
        #expect(resolve(.openAI, hasCloudKey: true).leavesTheMachine)
        #expect(resolve(.openAI, hasCloudKey: false).leavesTheMachine == false)
    }

    /// Pins the badge to the brain it is describing. These are computed from the
    /// same two facts in different files, and a disagreement would mean the
    /// panel naming one model while another answers.
    @Test("the badge agrees with the brain it describes")
    func agreesWithTheBrain() {
        let cloud = OpenAIBrain(apiKey: "sk-not-used", model: "gpt-4o-mini")
        #expect(resolve(.openAI, hasCloudKey: true).leavesTheMachine == cloud.leavesTheMachine)

        let local = OllamaBrain(endpoint: URL(string: "http://127.0.0.1:11434")!, model: "llama3.2")
        #expect(resolve(.ollama, hasCloudKey: false).leavesTheMachine == local.leavesTheMachine)
    }

    @Test("a missing key is explained by naming what is answering instead")
    func explainsTheFallback() {
        let explanation = resolve(.openAI, hasCloudKey: false).explanation(localModel: "llama3.2")

        #expect(explanation.contains("llama3.2"))
        #expect(explanation.contains("Settings"))
    }

    @Test("each choice has its own glyph")
    func glyphsAreDistinct() {
        let glyphs = [
            resolve(.ollama, hasCloudKey: false).glyph,
            resolve(.openAI, hasCloudKey: true).glyph,
            resolve(.openAI, hasCloudKey: false).glyph,
        ]
        #expect(Set(glyphs).count == glyphs.count)
    }
}

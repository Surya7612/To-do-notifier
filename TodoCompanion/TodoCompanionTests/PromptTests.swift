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

/// Follow-up turns are what make the panel usable for learning something step
/// by step, and they are also the easiest place to accidentally hand the model
/// the current question twice or let a conversation grow until the screen text
/// falls out of the context window.
@Suite("Conversation")
struct ConversationPromptTests {
    @Test("earlier turns are included, attributed to each speaker")
    func includesHistory() {
        let context = AskContext(history: [
            Turn(question: "what is this panel", answer: "The colour grading page."),
        ])
        let prompt = Prompt.user(question: "how do I use it", context: context)

        #expect(prompt.contains("Earlier in this conversation:"))
        #expect(prompt.contains("User: what is this panel"))
        #expect(prompt.contains("\(Prompt.assistantName): The colour grading page."))
    }

    @Test("the question still comes last, after the history")
    func questionComesAfterHistory() {
        let context = AskContext(history: [Turn(question: "first", answer: "answer")])
        let prompt = Prompt.user(question: "second", context: context)

        #expect(prompt.hasSuffix("Question: second"))
    }

    /// The screen text already dominates the prompt. An unbounded transcript
    /// would push it out of a small local model's window, so answers would get
    /// worse the longer the conversation went — the opposite of the intent.
    @Test("history is capped, keeping the most recent turns")
    func capsHistory() {
        let total = 12
        let turns = (1...total).map { Turn(question: "q\($0)", answer: "a\($0)") }
        let prompt = Prompt.user(question: "now", context: AskContext(history: turns))

        let oldestKept = total - Prompt.historyLimit + 1
        #expect(prompt.contains("User: q\(oldestKept)"))
        #expect(prompt.contains("User: q\(total)"))
        #expect(!prompt.contains("User: q\(oldestKept - 1)"), "older turns are dropped")
        #expect(!prompt.contains("User: q1\n"))
    }

    @Test("a first question carries no conversation section")
    func noHistorySectionOnFirstTurn() {
        let prompt = Prompt.user(question: "first thing", context: AskContext())

        #expect(!prompt.contains("Earlier in this conversation"))
    }

    @Test("the model is told a fresh capture describes the screen now")
    func explainsThatTheScreenMayHaveChanged() {
        #expect(Prompt.system.contains("screen may have changed"))
    }

    @Test("short follow-ups are to be read as being about the last answer")
    func handlesTerseFollowUps() {
        #expect(Prompt.system.contains("now what?"))
        #expect(Prompt.system.contains("do not repeat"))
    }
}

/// Asking a question empties the field, so `⌘S` afterwards has to find the
/// reason somewhere. What it settles on is stored as the user's own words,
/// which makes this a question about the app's central promise rather than a
/// convenience.
@Suite("What a save is filed under")
struct SavableReasonTests {
    @Test("the typed field wins whenever it has something in it")
    func typedFieldWins() {
        let turns = [Turn(question: "an earlier question", answer: "a")]

        #expect(Turn.savableReason(typed: "why I kept this", turns: turns) == "why I kept this")
    }

    @Test("with the field empty, the first typed question is used")
    func fallsBackToTheFirstQuestion() {
        let turns = [
            Turn(question: "how do I colour grade this", answer: "a"),
            Turn(question: "why that one", answer: "b"),
        ]

        #expect(Turn.savableReason(typed: "", turns: turns) == "how do I colour grade this")
    }

    /// "Explain what this is, in plain language" is the app's sentence. Storing
    /// it as the user's stated reason is the one thing `intent` must never do.
    @Test("preset wording is never stored as the user's reason")
    func presetsAreNotEligible() {
        let presetOnly = [Turn(question: "Explain what this is.", answer: "a", isFromPreset: true)]
        #expect(Turn.savableReason(typed: "", turns: presetOnly) == nil)

        let mixed = [
            Turn(question: "Explain what this is.", answer: "a", isFromPreset: true),
            Turn(question: "what does this node do", answer: "b"),
        ]
        #expect(Turn.savableReason(typed: "", turns: mixed) == "what does this node do")
    }

    @Test("nothing typed and nothing asked means there is no reason to save under")
    func nothingToSave() {
        #expect(Turn.savableReason(typed: "", turns: []) == nil)
        #expect(Turn.savableReason(typed: "   \n ", turns: []) == nil)
    }

    @Test("the typed reason is trimmed but otherwise kept verbatim")
    func keepsWordingVerbatim() {
        #expect(Turn.savableReason(typed: "  remind me tomorrow #resolve  ", turns: [])
            == "remind me tomorrow #resolve")
    }
}

/// Reaching the app you are asking about means clicking outside this one, which
/// dismisses the panel. So whether a conversation survives dismissal decides
/// whether follow-up questions work at all in the situation they exist for.
@Suite("Resuming a conversation")
struct ConversationResumeTests {
    private let now = Date()

    @Test("nothing to resume when there was no conversation")
    func noConversation() {
        #expect(!CompanionViewModel.conversationSurvives(lastTurnAt: nil, now: now))
    }

    @Test("a conversation just dismissed is still live")
    func recentSurvives() {
        let justNow = now.addingTimeInterval(-5)

        #expect(CompanionViewModel.conversationSurvives(lastTurnAt: justNow, now: now))
    }

    /// The point of the window: long enough to go and do the step you were told
    /// to do, then come back and ask what follows.
    @Test("a conversation survives long enough to act on the answer")
    func survivesDoingTheStep() {
        let twoMinutesAgo = now.addingTimeInterval(-120)

        #expect(CompanionViewModel.conversationSurvives(lastTurnAt: twoMinutesAgo, now: now))
    }

    @Test("a cold conversation is not resumed")
    func staleIsDropped() {
        let anHourAgo = now.addingTimeInterval(-3600)

        #expect(!CompanionViewModel.conversationSurvives(lastTurnAt: anHourAgo, now: now))
    }

    @Test("the boundary is inclusive, and just past it is not")
    func boundary() {
        let window = CompanionViewModel.conversationResumeWindow

        #expect(CompanionViewModel.conversationSurvives(
            lastTurnAt: now.addingTimeInterval(-window), now: now))
        #expect(!CompanionViewModel.conversationSurvives(
            lastTurnAt: now.addingTimeInterval(-window - 1), now: now))
    }
}

/// The persona is a tone. It must not become permission to invent, and the
/// editing instructions must not reach a question that has no file open.
@Suite("Persona and editing")
struct PersonaPromptTests {
    @Test("the assistant is named, and it is not the bundle name")
    func hasItsOwnName() {
        #expect(Prompt.assistantName == "Max")
        #expect(Prompt.system.contains("Max"))
    }

    /// A friendly voice is the classic way grounding rules get quietly
    /// loosened, so the prompt says outright that it does not.
    @Test("the persona is explicitly not a licence to invent")
    func personaDoesNotOverrideGrounding() {
        #expect(Prompt.system.contains("A persona is a tone, not a licence"))
        // The rules the persona sits on top of must all still be there.
        #expect(Prompt.system.contains("ground truth"))
        #expect(Prompt.system.contains("outrank"))
        #expect(Prompt.system.contains("say that instead of guessing"))
    }

    @Test("a teacher is asked for the next single action and to define jargon")
    func teachesRatherThanAsserts() {
        #expect(Prompt.system.contains("Define any jargon"))
        #expect(Prompt.system.contains("single next action"))
    }

    /// A question about the screen must never arrive with instructions about
    /// rewriting files attached.
    @Test("editing instructions appear only when a file is open")
    func editingRulesAreConditional() {
        let plain = AskContext()
        #expect(!Prompt.system(for: plain).contains("complete new contents"))

        let editing = AskContext(editableFile: EditableFileContext(name: "a.swift", contents: "let x = 1"))
        #expect(Prompt.system(for: editing).contains("complete new contents"))
    }

    @Test("the file is given with line numbers and named")
    func numbersTheFile() {
        let context = AskContext(editableFile: EditableFileContext(
            name: "Brain.swift",
            contents: "import Foundation\nlet x = 1"
        ))
        let prompt = Prompt.user(question: "improve this", context: context)

        #expect(prompt.contains("Brain.swift"))
        #expect(prompt.contains("1\timport Foundation"))
        #expect(prompt.contains("2\tlet x = 1"))
    }

    /// Abbreviating is what makes a whole-file reply unusable, and the failure
    /// is silent: the block applies cleanly and deletes most of the file.
    @Test("abbreviating the file is forbidden and applying is the user's call")
    func forbidsAbbreviationAndStatesWhoDecides() {
        #expect(Prompt.editingSystem.contains("rest unchanged"))
        #expect(Prompt.editingSystem.contains("Nothing you produce is applied on its own"))
    }

    /// A summary is a label in a list, not something said to anyone. The
    /// teaching persona writes a bad one.
    @Test("summarizing uses a prompt with no persona")
    func summariesHaveNoPersona() {
        #expect(!Prompt.summarySystem.contains(Prompt.assistantName))
        #expect(Prompt.summarySystem.contains("no persona"))
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

import Testing

@testable import TodoCompanion

/// This is inference deciding how a question gets answered, so what it needs to
/// guarantee is not accuracy but harmlessness: every branch must produce
/// guidance, none may withhold an answer, and the default must be the one that
/// assumes least. The classification cases below pin the shapes that were
/// actually getting the wrong advice.
@Suite("Reading what kind of thing is on screen")
struct ScreenKindTests {
    @Test("source code is recognized by its punctuation")
    func recognizesCode() {
        let screen = """
        func makeBrain() -> any Brain {
            guard let key = Keychain.read() else {
                return OllamaBrain()
            }
            return OpenAIBrain(key: key)
        }
        """

        #expect(ScreenKind.inferred(from: screen) == .code)
    }

    /// A shell shows code, so this has to be decided before the code test runs
    /// — otherwise every stack trace is taken for an editor and answered as
    /// though the user were reading the file rather than running it.
    @Test("a shell prompt outranks the code that follows it")
    func terminalBeatsCode() {
        let screen = """
        $ swift build
        error: cannot find 'Brain' in scope
            let brain = Brain()
                        ^~~~~
        """

        #expect(ScreenKind.inferred(from: screen) == .terminal)
    }

    @Test("a traceback with no prompt line is still a terminal")
    func recognizesTraceback() {
        let screen = """
        Traceback (most recent call last):
          File "run.py", line 12, in <module>
            main()
        KeyError: 'token'
        """

        #expect(ScreenKind.inferred(from: screen) == .terminal)
    }

    /// The word "error" is on screen in an editor showing a diagnostic, in a
    /// browser on a Stack Overflow page, and in a settings pane with a failed
    /// validation. None of them is a terminal.
    @Test("the word error alone does not make it a terminal")
    func errorWordIsNotEnough() {
        let screen = """
        Sign in
        Email address
        That email or password looks wrong. Please check for an error and try again.
        Forgot password?
        """

        #expect(ScreenKind.inferred(from: screen) != .terminal)
    }

    @Test("long sentence-shaped lines are a document")
    func recognizesProse() {
        let screen = """
        The companion distinguishes what the user said from what the model inferred, everywhere.
        Retrieval explains itself, so every resurfaced item carries a human-readable reason for it.
        A cloud model may answer a question the user explicitly asked, and may never do background work.
        The second rule concerns what leaves the machine, and it is enforced structurally rather than by convention.
        """

        #expect(ScreenKind.inferred(from: screen) == .prose)
    }

    /// The default, and the screen this app was built for: short labels, no
    /// sentence punctuation, nothing that looks like code.
    @Test("an application's chrome falls through to the interface case")
    func fallsBackToInterface() {
        let screen = """
        Media
        Edit
        Fusion
        Color
        Fairlight
        Deliver
        """

        #expect(ScreenKind.inferred(from: screen) == .interface)
    }

    @Test("too little text to judge is treated as an interface")
    func tooLittleTextIsInterface() {
        #expect(ScreenKind.inferred(from: "Save\nCancel") == .interface)
        #expect(ScreenKind.inferred(from: "") == .interface)
    }

    /// The safety property. A misread screen must cost a slightly oddly-shaped
    /// answer and nothing more, which means every branch has to say something
    /// and none of them may be the absence of guidance.
    @Test("every kind contributes guidance, so a wrong guess only reshapes an answer")
    func everyKindHasGuidance() {
        for kind in [ScreenKind.code, .terminal, .prose, .interface] {
            #expect(!kind.guidance.isEmpty)
        }
    }

    @Test("the screen's kind reaches the system prompt, and only through it")
    func guidanceReachesThePrompt() {
        let observation = Fixture.observation(text: """
        $ npm run dev
        sh: vite: command not found
        npm ERR! code 127
        npm ERR! path /Users/me/project
        """)

        let prompt = Prompt.system(for: AskContext(observation: observation))
        #expect(prompt.contains(ScreenKind.terminal.guidance))

        // And with nothing captured, no guess is made at all rather than the
        // default being asserted as though it had been observed.
        let blind = Prompt.system(for: AskContext())
        #expect(!blind.contains(ScreenKind.terminal.guidance))
        #expect(!blind.contains(ScreenKind.interface.guidance))
    }
}

/// The panel can only draw structure the model actually emits, so this half of
/// the feature lives in the prompt and is as load-bearing as the parser.
@Suite("Asking for a reply the panel can draw")
struct AnswerFormattingPromptTests {
    @Test("every question asks for fenced code with a language tag")
    func alwaysAsksForFences() {
        let prompt = Prompt.system(for: AskContext())

        #expect(prompt.contains("fenced block tagged"))
        #expect(prompt.contains("never as indented text"))
    }

    /// The four-sentence cap predates any of this and would otherwise be read
    /// as a reason to leave the code out.
    @Test("the length cap excludes code blocks and list items")
    func lengthCapDoesNotSuppressStructure() {
        #expect(Prompt.system.contains("four sentences of prose"))
        #expect(Prompt.system.contains("do not count towards that"))
    }
}

import CoreGraphics
import Foundation
import Testing

@testable import TodoCompanion

/// Reading a lesson out of an ordinary answer.
///
/// The reason this is worth testing is that the parse is the *only* thing
/// standing between a reply and a mode that draws on the user's screen. Both
/// directions fail silently: too eager and every answer containing a list puts
/// boxes over someone's editor, too reluctant and pressing "Teach me" appears
/// to do nothing at all.
@Suite("Reading a lesson out of an answer")
struct LessonParsingTests {
    private let walkthrough = """
    Here is what is going wrong.

    1. Look at "return re" on line 19 — that is Python's regular-expression module.
    2. Compare it with "res", the list you have been appending to.
    3. The call on line 17, "backtrack(0, []", is missing its closing bracket.
    """

    @Test("a numbered walkthrough becomes steps, in order")
    func numberedListBecomesSteps() throws {
        let lesson = try #require(Lesson.from(answer: walkthrough))

        #expect(lesson.steps.count == 3)
        #expect(lesson.steps[0].anchors == ["return re"])
        #expect(lesson.steps[1].anchors == ["res"])
        #expect(lesson.steps[2].anchors == ["backtrack(0, []"])
    }

    /// The introduction is prose, not a step. Treating it as one would open the
    /// lesson on a step that points at nothing.
    @Test("prose around the list is not mistaken for a step")
    func introductionIsNotAStep() throws {
        let lesson = try #require(Lesson.from(answer: walkthrough))

        #expect(!lesson.steps.contains { $0.text.contains("Here is what") })
    }

    @Test("an answer with no list is not a lesson")
    func proseIsNotALesson() {
        #expect(Lesson.from(answer: "The bug is on line 19. Change re to res.") == nil)
    }

    /// The failure that matters most, because it is the one that would put an
    /// empty mode over a perfectly good answer: a small model asked for steps
    /// sometimes writes a paragraph instead.
    @Test("a list too short to be worth a mode is refused")
    func aShortListIsNotALesson() {
        let answer = """
        1. Rename "re" to "res".
        2. Run it again.
        """

        #expect(Lesson.from(answer: answer) == nil)
    }

    /// A numbered list is a common way to write an answer that has nothing to
    /// do with what is on screen. Without this, "1. sort 2. recurse 3. undo"
    /// would start a lesson whose every step drew nothing.
    @Test("a list that quotes nothing on screen is not a lesson")
    func aListNamingNothingIsNotALesson() {
        let answer = """
        1. Sort the input first.
        2. Recurse into the remaining elements.
        3. Undo the choice before returning.
        """

        #expect(Lesson.from(answer: answer) == nil)
    }

    /// Steps that quote nothing are kept when *some* step does. They are still
    /// worth saying; they simply draw nothing while they are said.
    @Test("a step naming nothing survives inside a lesson that does name things")
    func stepsWithoutAnchorsAreKept() throws {
        let answer = """
        1. Start by reading "subsetsWithDup" from the top.
        2. Think about what duplicates would do here.
        3. Now look at "nums.sort()" and say why it comes first.
        """

        let lesson = try #require(Lesson.from(answer: answer))

        #expect(lesson.steps.count == 3)
        #expect(lesson.steps[1].anchors.isEmpty)
    }
}

/// Following the voice through a lesson.
/// The two things a step carries besides its boxes. Both reach the user's own
/// screen, so both are asserted rather than eyeballed: a caption is drawn over
/// their work, and an arrow is a claim that one thing becomes another.
@Suite("What a step draws besides boxes")
struct LessonMarkTests {
    @Test("an arrow between two quoted labels asks for a connector")
    func statedRelationConnects() throws {
        let lesson = try #require(Lesson.from(answer: """
        1. The value in "res" is what "return res" hands back \u{2192} they are the same list.
        2. The call to "backtrack" is where it is filled in.
        3. The guard on "if start == len(nums)" is the base case.
        """))

        #expect(lesson.steps[0].isConnected)
        // Two labels in one step is not a relation between them. Only Max
        // writing the arrow is.
        #expect(!lesson.steps[1].isConnected)
    }

    @Test("a caption is the step's opening, cut at a word")
    func captionIsCutAtAWord() throws {
        let lesson = try #require(Lesson.from(answer: """
        1. This step is deliberately much longer than a caption should ever be, so that the cut has \
        somewhere to happen and we can watch it land on a space rather than mid-word.
        2. A short one about "res".
        3. Another short one about "nums".
        """))

        let caption = lesson.steps[0].caption
        #expect(caption.count <= Lesson.captionLength + 1)
        #expect(caption.hasSuffix("…"))
        #expect(!caption.contains(" …"))

        // Short enough to print in full, so nothing is taken off it.
        #expect(lesson.steps[1].caption == #"A short one about "res"."#)
    }

    @Test("curly quotes in a caption are printed as plain ones")
    func captionNormalizesQuotes() throws {
        let lesson = try #require(Lesson.from(answer: """
        1. Look at \u{201C}res\u{201D} first.
        2. Then at "nums".
        3. Then at "start".
        """))

        #expect(lesson.steps[0].caption == #"Look at "res" first."#)
    }
}

@Suite("Which step is being spoken")
struct LessonPlaybackTests {
    private let lesson = Lesson(steps: [
        .init(text: "First look at \"nums\".", anchors: ["nums"], isConnected: false),
        .init(text: "Then at \"res\".", anchors: ["res"], isConnected: false),
        .init(text: "Finally \"return res\".", anchors: ["return res"], isConnected: false),
    ])

    @Test("a clause quoting a later label advances to that step")
    func quotedLabelAdvances() {
        #expect(lesson.step(spokenIn: "Then at \"res\".", notBefore: 0) == 1)
    }

    /// Speech arrives in order, so a label mentioned again later must not drag
    /// the lesson back to the first step that used it.
    @Test("a label used again never moves the lesson backwards")
    func matchingNeverGoesBackwards() {
        #expect(lesson.step(spokenIn: "Remember \"nums\" from earlier.", notBefore: 2) == nil)
    }

    /// Most sentences of a lesson are elaboration on the step already showing.
    /// Clearing or moving the marks for those would flicker the screen.
    @Test("a clause quoting nothing leaves the step where it is")
    func unquotedClauseDoesNotMove() {
        #expect(lesson.step(spokenIn: "That is the usual mistake here.", notBefore: 0) == nil)
    }

    /// The matching happens after `SpeechPlayback` has stripped markup, so it
    /// has to keep working on the text the voice actually reports.
    @Test("matching survives the stripping the voice does first")
    func matchingSurvivesSpeechStripping() {
        let spoken = SpeechPlayback.speakable(from: "2. Then at **\"res\"**, the list you built.")

        #expect(lesson.step(spokenIn: spoken, notBefore: 0) == 1)
    }
}

/// Resolving several labels at once, which is what a step needs and `locate`
/// does not do.
@Suite("Finding every label a step names")
struct LessonAnchorTests {
    private func regions(_ words: [String], line: Int = 0) -> [TextRegion] {
        words.enumerated().map { position, word in
            TextRegion(string: word,
                       boundingBox: CGRect(x: 0.1 * Double(position), y: 0.5,
                                           width: 0.08, height: 0.02),
                       line: line,
                       position: position)
        }
    }

    @Test("each label that is on screen gets its own box")
    func everyLabelResolves() {
        let onScreen = regions(["return", "res", "backtrack"])

        let found = ScreenTextLocator.locate(labels: ["backtrack", "res"], in: onScreen)

        #expect(found.map(\.text) == ["backtrack", "res"])
    }

    /// A step that boxes two of the three things it mentions is still useful.
    /// A box over the wrong words is not, which is why this drops rather than
    /// approximates.
    @Test("a label Vision never saw is dropped, not approximated")
    func missingLabelsAreDropped() {
        let found = ScreenTextLocator.locate(labels: ["res", "Submit"], in: regions(["return", "res"]))

        #expect(found.map(\.text) == ["res"])
    }

    /// Vision splits a label across one region per word, so the box has to be
    /// the union of the run rather than of whichever word matched first.
    @Test("a multi-word label is boxed whole")
    func multiWordLabelSpansItsWords() throws {
        let found = try #require(
            ScreenTextLocator.locate(label: "return res", in: regions(["return", "res"]))
        )

        #expect(found.text == "return res")
        #expect(found.boundingBox.width > 0.08)
    }

    @Test("labels are ordered as Max named them, and repeats collapse")
    func quotedLabelsKeepOrder() {
        let labels = ScreenTextLocator.quotedLabels(in: "Compare \"res\" with \"re\", then \"res\" again.")

        #expect(labels == ["res", "re"])
    }
}

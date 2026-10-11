import CoreGraphics
import Foundation
import Testing
@testable import TodoCompanion

@Suite("Change-aware re-save")
struct ScreenChangeTests {
    @Test("new and gone tokens are named in the summary line")
    func namesAddedAndRemoved() throws {
        let summary = try #require(
            ScreenChange.summary(previous: "func crash handler nil",
                                 current: "func crash handler fixed retry")
        )
        #expect(summary.addedCount > 0)
        #expect(summary.line.contains("new:"))
        #expect(summary.line.contains("Since last keep"))
    }

    @Test("identical OCR yields an unchanged line rather than nil")
    func unchangedIsStated() throws {
        let summary = try #require(
            ScreenChange.summary(previous: "same tokens here",
                                 current: "same tokens here")
        )
        #expect(summary.addedCount == 0)
        #expect(summary.removedCount == 0)
        #expect(summary.line.contains("unchanged"))
    }

    @Test("prior keep prefers the same window over the same app")
    func priorKeepPrefersWindow() {
        let older = Fixture.saved(intent: "old", app: "Xcode", window: "Brain.swift", daysOld: 2)
        older.recognizedText = "older text"
        let newer = Fixture.saved(intent: "new", app: "Xcode", window: "Brain.swift", daysOld: 0)
        newer.recognizedText = "newer text"
        let other = Fixture.saved(intent: "other", app: "Xcode", window: "Other.swift")
        let screen = Fixture.observation(app: "Xcode", window: "Brain.swift")

        let prior = ScreenChange.priorKeep(for: screen, among: [older, newer, other])
        #expect(prior?.intent == "new")
    }
}

@Suite("Project brief and standup prep")
struct ContinuityPromptTests {
    @Test("a brief needs at least one keep, task, or due reminder")
    func briefNeedsMaterial() {
        #expect(ProjectBrief.askPrompt(projectName: "Engram",
                                       intents: [],
                                       openTaskTitles: [],
                                       dueSoonIntents: []) == nil)
    }

    @Test("a brief quotes the user's own intents, not invented ones")
    func briefUsesUserWords() throws {
        let prompt = try #require(
            ProjectBrief.askPrompt(projectName: "Engram",
                                   intents: ["wire retrieval", "fix quiet hours"],
                                   openTaskTitles: ["Ship demo"],
                                   dueSoonIntents: ["remind me to record"])
        )
        #expect(prompt.contains("Engram"))
        #expect(prompt.contains("wire retrieval"))
        #expect(prompt.contains("Ship demo"))
        #expect(prompt.contains("remind me to record"))
        #expect(prompt.contains("do not invent"))
    }

    @Test("standup prep structures yesterday / today / blockers")
    func standupStructure() {
        let prompt = StandupPrep.askPrompt(projectName: "Engram",
                                           openTaskTitles: ["Ship demo"],
                                           dueSoonIntents: [],
                                           recentKeepIntents: ["wire retrieval"])
        #expect(prompt.contains("yesterday / today / blockers"))
        #expect(prompt.contains("Ship demo"))
        #expect(prompt.contains("wire retrieval"))
        #expect(prompt.contains("Do not invent"))
    }

    @Test("standup with nothing listed still asks what was worked on")
    func emptyStandupAsks() {
        let prompt = StandupPrep.askPrompt(projectName: nil,
                                           openTaskTitles: [],
                                           dueSoonIntents: [],
                                           recentKeepIntents: [])
        #expect(prompt.contains("No tasks or saves"))
    }
}

@Suite("Answer grounding badge")
struct AnswerGroundingTests {
    @Test("screenshot, OCR-only, and no-capture stay distinguishable")
    func threeModes() {
        #expect(AnswerGrounding.mode(hasCapture: true, sendsImage: true) == .seesScreenshot)
        #expect(AnswerGrounding.mode(hasCapture: true, sendsImage: false) == .ocrOnly)
        #expect(AnswerGrounding.mode(hasCapture: false, sendsImage: true) == .noCapture)

        #expect(AnswerGrounding.badgeLabel(for: .seesScreenshot) == "Sees screen")
        #expect(AnswerGrounding.badgeLabel(for: .ocrOnly) == "Text only")
        #expect(AnswerGrounding.badgeLabel(for: .noCapture) == nil)
    }
}

@Suite("Lesson Markdown export")
struct LessonExportTests {
    @Test("markdown keeps step order and quoted anchors")
    func markdownKeepsQuotes() throws {
        let lesson = try #require(Lesson.from(answer: """
        1. Look at "return re" on line 19.
        2. Compare it with "res".
        3. Fix the call to "backtrack".
        """))
        let md = lesson.markdown(title: "Brain.swift")
        #expect(md.hasPrefix("# Brain.swift"))
        #expect(md.contains("1. "))
        #expect(md.contains("\"return re\""))
        #expect(md.contains("\"res\""))
        #expect(md.contains("3. "))
    }
}

@Suite("Multi-display pointing surfaces")
struct PointingSurfacesTests {
    @Test("a match on a secondary display maps into that display's frame")
    func secondaryDisplayHit() throws {
        let primary = CapturedDisplay(
            image: Fixture.blankImage(),
            index: 1,
            textRegions: [
                TextRegion(string: "Cancel",
                           boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.1, height: 0.05),
                           line: 0,
                           position: 0),
            ],
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let secondary = CapturedDisplay(
            image: Fixture.blankImage(),
            index: 2,
            textRegions: [
                TextRegion(string: "Submit",
                           boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.15, height: 0.05),
                           line: 0,
                           position: 0),
            ],
            screenFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800)
        )
        var observation = ScreenObservation(
            primary: primary,
            others: [secondary],
            appName: "Safari",
            windowTitle: "Form"
        )
        observation.primaryScreenFrame = primary.screenFrame

        let hit = try #require(observation.locatePointable(named: #"Click "Submit""#))
        #expect(hit.match.text == "Submit")
        #expect(hit.frame.origin.x == 1000)
    }

    @Test("a quoted label on a secondary display beats a short primary hit")
    func quotedSecondaryBeatsPrimary() throws {
        let primary = CapturedDisplay(
            image: Fixture.blankImage(),
            index: 1,
            textRegions: [
                TextRegion(string: "OK",
                           boundingBox: CGRect(x: 0.1, y: 0.1, width: 0.05, height: 0.05),
                           line: 0,
                           position: 0),
            ],
            screenFrame: CGRect(x: 0, y: 0, width: 1000, height: 800)
        )
        let secondary = CapturedDisplay(
            image: Fixture.blankImage(),
            index: 2,
            textRegions: [
                TextRegion(string: "Confirm",
                           boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.2, height: 0.05),
                           line: 0,
                           position: 0),
            ],
            screenFrame: CGRect(x: 1000, y: 0, width: 1000, height: 800)
        )
        var observation = ScreenObservation(
            primary: primary,
            others: [secondary],
            appName: "Xcode",
            windowTitle: "Alert"
        )
        observation.primaryScreenFrame = primary.screenFrame

        let hit = try #require(observation.locatePointable(named: #"Press "Confirm" when ready"#))
        #expect(hit.match.text == "Confirm")
        #expect(hit.frame.origin.x == 1000)
    }
}

import Foundation
import Testing
@testable import TodoCompanion

@Suite("Session modes")
struct SessionModeTests {
    @Test("every mode contributes guidance and none withhold an answer")
    func everyModeGuides() {
        for mode in SessionMode.allCases {
            #expect(!mode.guidance.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            #expect(mode.title.count >= 3)
        }
    }

    @Test("Teach prefers lessons and boards; Debug does not force a walk")
    func stanceFlags() {
        #expect(SessionMode.teach.prefersTeaching)
        #expect(SessionMode.teach.prefersBoard)
        #expect(!SessionMode.debug.prefersTeaching)
        #expect(!SessionMode.debug.prefersBoard)
        #expect(SessionMode.ask.prefersBoard)
        #expect(!SessionMode.prep.prefersTeaching)
    }

    @Test("system prompt carries the chosen stance")
    func systemCarriesMode() {
        let teach = Prompt.system(for: AskContext(sessionMode: .teach))
        #expect(teach.contains("Session mode is Teach"))

        let debug = Prompt.system(for: AskContext(sessionMode: .debug))
        #expect(debug.contains("Session mode is Debug"))
        #expect(debug.contains("smallest next action"))
    }
}

@Suite("Problem tutor")
struct ProblemTutorTests {
    @Test("LeetCode chrome activates the tutor")
    func leetCodeShape() {
        let text = """
        LeetCode
        1. Two Sum
        Easy
        Given an array of integers nums and an integer target, return indices…
        Example 1:
        Constraints:
        """
        #expect(ProblemTutor.inferred(from: text) == .codingProblem)
        #expect(ProblemTutor.inferred(from: text).guidance != nil)
    }

    @Test("ordinary editor code stays inactive")
    func ordinaryCode() {
        let text = """
        func greet(name: String) -> String {
            return "hello \\(name)"
        }
        """
        #expect(ProblemTutor.inferred(from: text) == .inactive)
        #expect(ProblemTutor.inferred(from: text).guidance == nil)
    }

    @Test("two shape phrases without a platform still light the tutor")
    func shapeWithoutPlatform() {
        let text = "Given an array nums, return the majority element. Example 1: Input: [3,2,3]"
        #expect(ProblemTutor.inferred(from: text) == .codingProblem)
    }

    @Test("tutor guidance lands in the system prompt only when active")
    func guidanceIsConditional() {
        let plain = Prompt.system(for: AskContext(problemTutor: .inactive))
        #expect(!plain.contains("coding problem"))

        let tutor = Prompt.system(for: AskContext(problemTutor: .codingProblem))
        #expect(tutor.contains("coding problem"))
        #expect(tutor.contains("No full editorial") || tutor.contains("editorial"))
        #expect(tutor.contains("sketch explainer") || tutor.contains("15–30"))
        #expect(tutor.contains("Example") || tutor.contains("example"))
        #expect(tutor.contains("true and false") || tutor.contains("contrast"))
    }
}

@Suite("Teach memory and page structure")
struct TeachEnrichmentPromptTests {
    @Test("related keeps are named in the teach system prompt")
    func memoriesSurfaceInTeach() {
        let bare = Prompt.system(for: AskContext(memories: [], isTeaching: true))
        #expect(!bare.contains("kept related notes before"))

        let withMemory = Prompt.system(for: AskContext(
            memories: ["- \"two pointers on sorted arrays\""],
            isTeaching: true
        ))
        #expect(withMemory.contains("kept related notes before"))
        #expect(withMemory.contains("Never invent a keep"))
    }

    @Test("AX page text is labelled separately from OCR")
    func pageStructureIsLabelled() {
        let prompt = Prompt.user(
            question: "explain the problem",
            context: AskContext(
                observation: Fixture.observation(text: "ocr line"),
                pageStructure: "Two Sum\nGiven an array of integers"
            )
        )
        #expect(prompt.contains("Accessibility text from the focused app"))
        #expect(prompt.contains("Two Sum"))
        #expect(prompt.contains("Text visible on screen:"))
        #expect(prompt.contains("ocr line"))
    }

    @Test("MCP tool notes are labelled as tools, not user intent")
    func toolNotesAreLabelled() {
        let context = AskContext(toolNotes: ["- [search] prior notes on DP"])
        let system = Prompt.system(for: context)
        let user = Prompt.user(question: "teach this", context: context)
        #expect(system.contains("MCP servers the user enabled"))
        #expect(user.contains("MCP tool results"))
        #expect(user.contains("not the user's words"))
        #expect(user.contains("[search] prior notes on DP"))
    }
}

@Suite("MCP tool selection")
struct MCPClientSelectionTests {
    @Test("lexical overlap ranks matching tools first")
    func ranksByOverlap() {
        let tools = [
            MCPClient.Tool(name: "weather", description: "forecast for a city"),
            MCPClient.Tool(name: "notes_search", description: "search your kept notes"),
            MCPClient.Tool(name: "calendar", description: "upcoming events"),
        ]
        let chosen = MCPClient.selectTools(tools, for: "search my notes about DP", limit: 2)
        #expect(chosen.first?.name == "notes_search")
        #expect(chosen.count <= 2)
    }

    @Test("no overlap still offers the first tool so a one-tool server works")
    func fallbackToFirst() {
        let tools = [MCPClient.Tool(name: "only_search", description: "find things")]
        let chosen = MCPClient.selectTools(tools, for: "zzzz", limit: 3)
        #expect(chosen.map(\.name) == ["only_search"])
    }

    @Test("prompt lines keep the tool name visible")
    func promptLinesNameTools() {
        let lines = MCPClient.promptLines(for: [
            .init(tool: "notes_search", text: "two pointers"),
        ])
        #expect(lines == ["- [notes_search] two pointers"])
    }

    @Test("enrich is a no-op when disabled or launch is empty")
    func enrichGuards() async {
        let off = await MCPClient.enrich(question: "anything", launch: ["npx"], enabled: false)
        #expect(off.notes.isEmpty)
        #expect(off.problem == nil)
        let empty = await MCPClient.enrich(question: "anything", launch: [], enabled: true)
        #expect(empty.notes.isEmpty)
        #expect(empty.problem == nil)
    }
}

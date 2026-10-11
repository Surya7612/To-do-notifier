import Foundation

/// Whether the screen looks like a coding-problem tutor should take over.
///
/// Pure OCR heuristics — LeetCode, HackerRank, Advent of Code, and plain
/// "Given an array…" statements. Being wrong is cheap: the guidance only
/// reshapes the lesson; it never opens a browser or clicks anything.
nonisolated enum ProblemTutor: Equatable, Sendable {
    case inactive
    case codingProblem

    /// Signals that this text is a problem statement rather than ordinary code.
    static func inferred(from text: String) -> ProblemTutor {
        let lower = text.lowercased()
        let platform = [
            "leetcode", "hackerrank", "hackerearth", "codeforces", "atcoder",
            "advent of code", "interviewbit", "neptune", "codesignal",
        ]
        if platform.contains(where: { lower.contains($0) }) {
            return .codingProblem
        }

        let shape = [
            "given an array", "given a string", "given a binary tree",
            "given a graph", "return the", "write a function",
            "example 1:", "example 2:", "constraints:", "input:", "output:",
            "follow-up:", "follow up:", "time complexity", "o(n)",
        ]
        let hits = shape.filter { lower.contains($0) }.count
        if hits >= 2 { return .codingProblem }

        // Title-case "Easy" / "Medium" / "Difficulty" next to problem chrome.
        let platformChrome = lower.contains("difficulty")
            || (lower.contains("accepted") && lower.contains("submission"))
        if platformChrome,
           lower.contains("easy") || lower.contains("medium") || lower.contains("hard") {
            return .codingProblem
        }

        return .inactive
    }

    var guidance: String? {
        switch self {
        case .inactive:
            return nil
        case .codingProblem:
            return """
            The screen looks like a coding problem. Teach it as a 15–30s sketch explainer, not a \
            solution dump: (1) one sentence goal + pattern, (2) 4–6 numbered beats that walk one \
            story on the Example numbers — setup → try → result → optional contrast case in a \
            later beat (never true and false in the same breath), (3) quote only literal on-screen \
            text when pointing; concept beats use the board as sequential video frames (same cast \
            each cut: counters, cars, map cells, or client→API→DB), (4) complexity after the walk. \
            No full editorial. If the editor shows their attempt, teach from that.
            """
        }
    }
}

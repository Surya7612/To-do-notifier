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
            The screen looks like a coding problem. Teach it like an interview coach, not a \
            solution dump. In the numbered steps: first explain the concept the problem is named \
            after as if they have never heard of it — what an LRU cache is and why caches evict, \
            what a trie is — with an everyday analogy; then what the problem is actually asking, \
            in plain words; say exactly \
            what the function receives and returns, and which constraint rules out the brute force; \
            name the topics it tests (e.g. "hash map", "doubly linked list", "sliding window") and \
            why those fit; then walk Example 1 with its real numbers, one operation per step, saying \
            the state after each — setup → try → result, with any contrast case in a later step \
            (never true and false in the same breath); then one edge case; then the approach in \
            one sentence. After the list: time and space complexity, and one question for them to \
            check themselves with. Quote only literal on-screen text when pointing; the board \
            draws the real data structure each step. No full editorial — code only if they asked \
            for it. If the editor shows their attempt, teach from that.
            """
        }
    }
}

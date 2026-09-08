import Foundation

/// A line-by-line comparison of two versions of a file.
///
/// Computed here rather than asked of the model. A model emitting a unified
/// diff gets line numbers and context lines wrong often enough that the patch
/// will not apply, and worse, a wrong diff *looks* authoritative. A diff
/// derived from the two texts cannot be wrong about what changed, because it
/// is the definition of what changed.
///
/// `nonisolated` because the project builds with default MainActor isolation
/// and this is pure computation over strings.
nonisolated enum TextDiff {
    struct Line: Equatable, Identifiable {
        enum Kind: Equatable {
            case unchanged
            case added
            case removed
        }

        let id: Int
        let kind: Kind
        let text: String
        /// Line number in the original file, absent for an added line.
        let oldNumber: Int?
        /// Line number in the proposed file, absent for a removed line.
        let newNumber: Int?
    }

    struct Summary: Equatable {
        var added = 0
        var removed = 0

        var isEmpty: Bool { added == 0 && removed == 0 }

        var description: String {
            isEmpty ? "No change" : "+\(added) −\(removed)"
        }
    }

    /// - Returns: every line of both files, in order, tagged with what happened
    ///   to it. Callers that only want the changed parts use `hunks`.
    static func compare(_ original: String, to proposed: String) -> [Line] {
        let old = original.components(separatedBy: .newlines)
        let new = proposed.components(separatedBy: .newlines)

        var lines: [Line] = []
        var identifier = 0
        func append(_ kind: Line.Kind, _ text: String, old oldNumber: Int?, new newNumber: Int?) {
            lines.append(Line(id: identifier, kind: kind, text: text,
                              oldNumber: oldNumber, newNumber: newNumber))
            identifier += 1
        }

        let table = longestCommonSubsequenceLengths(old, new)
        var i = 0, j = 0
        while i < old.count, j < new.count {
            if old[i] == new[j] {
                append(.unchanged, old[i], old: i + 1, new: j + 1)
                i += 1
                j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                append(.removed, old[i], old: i + 1, new: nil)
                i += 1
            } else {
                append(.added, new[j], old: nil, new: j + 1)
                j += 1
            }
        }
        while i < old.count {
            append(.removed, old[i], old: i + 1, new: nil)
            i += 1
        }
        while j < new.count {
            append(.added, new[j], old: nil, new: j + 1)
            j += 1
        }

        return lines
    }

    static func summary(of lines: [Line]) -> Summary {
        var summary = Summary()
        for line in lines {
            switch line.kind {
            case .added: summary.added += 1
            case .removed: summary.removed += 1
            case .unchanged: break
            }
        }
        return summary
    }

    /// The changed regions, each with a few unchanged lines around it.
    ///
    /// A whole file is unreadable in a 468pt panel, and the user is being asked
    /// to approve a change — they need to see what changed, with enough
    /// surrounding code to recognise where it is.
    static func hunks(_ lines: [Line], context: Int = 3) -> [[Line]] {
        let changedIndices = lines.indices.filter { lines[$0].kind != .unchanged }
        guard !changedIndices.isEmpty else { return [] }

        var ranges: [ClosedRange<Int>] = []
        for index in changedIndices {
            let lower = max(0, index - context)
            let upper = min(lines.count - 1, index + context)

            // Merged when they touch or overlap, so two edits three lines apart
            // read as one region rather than as two with a repeated line.
            if let last = ranges.last, lower <= last.upperBound + 1 {
                ranges[ranges.count - 1] = last.lowerBound...max(last.upperBound, upper)
            } else {
                ranges.append(lower...upper)
            }
        }

        return ranges.map { Array(lines[$0]) }
    }

    /// Classic dynamic-programming LCS table. `table[i][j]` is the length of
    /// the longest common subsequence of `old[i...]` and `new[j...]`, so the
    /// walk above can decide each step by looking one cell ahead.
    private static func longestCommonSubsequenceLengths(_ old: [String], _ new: [String]) -> [[Int]] {
        var table = [[Int]](repeating: [Int](repeating: 0, count: new.count + 1),
                            count: old.count + 1)
        for i in stride(from: old.count - 1, through: 0, by: -1) {
            for j in stride(from: new.count - 1, through: 0, by: -1) {
                table[i][j] = old[i] == new[j]
                    ? table[i + 1][j + 1] + 1
                    : max(table[i + 1][j], table[i][j + 1])
            }
        }
        return table
    }
}

/// Pulls the proposed file out of a model's reply.
nonisolated enum CodeBlock {
    /// - Returns: the contents of the last fenced block, or nil if the reply
    ///   has none.
    ///
    /// The *last* block because explanations often quote the offending lines
    /// first and the rewrite comes after. An unterminated fence yields nil
    /// rather than everything to the end of the reply, since a truncated file
    /// written to disk is the worst outcome available here.
    static func extract(from reply: String) -> String? {
        let lines = reply.components(separatedBy: .newlines)

        var blocks: [[String]] = []
        var current: [String]?
        for line in lines {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                if let open = current {
                    blocks.append(open)
                    current = nil
                } else {
                    current = []
                }
            } else {
                current?.append(line)
            }
        }

        guard let block = blocks.last else { return nil }
        let contents = block.joined(separator: "\n")
        return contents.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : contents
    }
}

import Foundation

/// What sort of thing the screen appears to be showing.
///
/// Read off the OCR text, and used for exactly one purpose: choosing which
/// extra paragraph of instruction goes into the system prompt. That limit is
/// the point. The app's rule is that inference may suggest and never act, and a
/// guess that shapes *how* a question is answered is a suggestion — where the
/// same guess stored as the user's stated reason, or drawn on their screen,
/// would not be.
///
/// It is therefore built so that being wrong is cheap. Every branch adds
/// guidance that is merely unhelpful on the wrong screen; none of them tells
/// the model to do something categorically different, and none of them can
/// suppress an answer. A misread terminal produces a slightly oddly-shaped
/// answer about code, not a refusal.
nonisolated enum ScreenKind: Equatable {
    /// Source code, in an editor or a diff.
    case code
    /// A shell, a log, or a stack trace.
    case terminal
    /// A document, article, or page of writing.
    case prose
    /// An application's controls — the default, and what this app was built for.
    case interface

    /// Below this there is not enough text to say anything, and the default is
    /// the one that assumes least.
    static let minimumLines = 4

    static func inferred(from text: String) -> ScreenKind {
        let lines = text.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        guard lines.count >= minimumLines else { return .interface }

        // Terminal first: a shell shows code, so testing for code before this
        // would take every stack trace for an editor.
        if isTerminal(lines) { return .terminal }

        let share = { (matching: (String) -> Bool) in
            Double(lines.filter(matching).count) / Double(lines.count)
        }

        if share(isCodeLike) >= 0.3 { return .code }
        if share(isProseLike) >= 0.3 { return .prose }
        return .interface
    }

    /// A shell prompt or a stack trace, both of which are unmistakable.
    ///
    /// Deliberately not "contains the word error": an editor showing a compiler
    /// diagnostic, a browser on a Stack Overflow question and a settings pane
    /// with a validation message all contain it, and none of them is a terminal.
    private static func isTerminal(_ lines: [String]) -> Bool {
        let promptMarkers = ["$ ", "% ", "❯ ", "➜ ", "> "]
        let traceMarkers = [
            "traceback (most recent call last)", "command not found", "npm err!",
            "no such file or directory", "permission denied", "segmentation fault",
            "core dumped", "at /", "exit code",
        ]

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if promptMarkers.contains(where: { trimmed.hasPrefix($0) }) { return true }

            let lowercased = trimmed.lowercased()
            if traceMarkers.contains(where: { lowercased.contains($0) }) { return true }
        }

        return false
    }

    private static let codeKeywords: Set<String> = [
        "func", "def", "class", "struct", "enum", "import", "from", "return",
        "const", "let", "var", "if", "for", "while", "public", "private", "static",
        "async", "await", "extension", "interface", "type", "package", "namespace",
    ]

    private static func isCodeLike(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Punctuation carries most of the signal. Prose contains commas and
        // full stops; it does not contain braces, semicolons or arrows.
        if trimmed.contains("{") || trimmed.contains("}") || trimmed.contains(";")
            || trimmed.contains("=>") || trimmed.contains("->") || trimmed.contains("()") {
            return true
        }

        let firstWord = trimmed.prefix { $0.isLetter }
        // Indentation on its own says nothing — a bulleted list is indented too
        // — so it only counts alongside a keyword opening the line.
        return codeKeywords.contains(String(firstWord))
    }

    /// A line of a document: long, sentence-punctuated, and free of the
    /// punctuation that code and interfaces are made of.
    private static func isProseLike(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 60 else { return false }
        guard !isCodeLike(trimmed) else { return false }

        let words = trimmed.split(separator: " ")
        guard words.count >= 10 else { return false }

        return trimmed.contains(". ") || trimmed.hasSuffix(".") || trimmed.contains(", ")
    }
}

extension ScreenKind {
    /// The paragraph appended to the system prompt for this kind of screen.
    ///
    /// Each one narrows *how* to answer rather than *whether* to, so that the
    /// worst case of a misread screen is advice shaped for the wrong material.
    var guidance: String {
        switch self {
        case .code:
            """
            The screen is showing source code. Spell identifiers exactly as they appear, including \
            case, and say which function or line you mean rather than "the loop" or "that part". \
            When you propose a change, show only the lines that change, in a fenced block — not the \
            surrounding file.
            """

        case .terminal:
            """
            The screen is showing a terminal or a log. Lead with what went wrong and why, then give \
            exactly one command to run next in a fenced block. Read the whole output before \
            answering: the line naming the cause usually sits well above the last line, and the \
            last line is often only where the failure surfaced.
            """

        case .prose:
            """
            The screen is showing a document rather than an interface. When you refer to a passage, \
            quote a short phrase from it exactly as printed, so the user can find the place you \
            mean. There are no controls to name here, so do not invent one.
            """

        case .interface:
            """
            The screen is showing an application's controls. This is where the quoting rule matters \
            most: give the single next click, and put the control's printed label in double quotes \
            so it can be found on screen.
            """
        }
    }
}

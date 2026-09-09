import SwiftUI

/// Colours the tokens in a fenced code block.
///
/// Hand-rolled and deliberately shallow: it knows about comments, strings,
/// numbers and a list of keywords, and nothing whatever about grammar. A real
/// parser per language would be a dependency and a permanent maintenance
/// surface, and almost all of the value here is in separating the parts of code
/// that are prose — comments and string literals — from the parts that are
/// structure. Lexical rules get that right.
///
/// Being wrong is cheap in a way a wrong screen highlight is not: the text is
/// still exactly what the model returned, and the reader can see it.
nonisolated enum CodeHighlighter {
    static func highlight(_ code: String, language: String?) -> AttributedString {
        let syntax = Syntax.named(language)
        var result = AttributedString()
        // Carried across lines, since a block comment is the one token that
        // does not end where the line does.
        var isInsideBlockComment = false

        for (offset, line) in code.components(separatedBy: .newlines).enumerated() {
            if offset > 0 { result += AttributedString("\n") }
            result += highlighted(line: line,
                                  syntax: syntax,
                                  isInsideBlockComment: &isInsideBlockComment)
        }

        return result
    }

    private static func highlighted(line: String,
                                    syntax: Syntax,
                                    isInsideBlockComment: inout Bool) -> AttributedString {
        var result = AttributedString()
        let characters = Array(line)
        var index = 0
        var plain = ""

        func flushPlain() {
            guard !plain.isEmpty else { return }
            result += words(in: plain, syntax: syntax)
            plain = ""
        }

        while index < characters.count {
            if isInsideBlockComment {
                let start = index
                isInsideBlockComment = consumeBlockComment(characters, from: &index)
                result += token(String(characters[start..<index]), colour: DS.Code.comment)
                continue
            }

            if syntax.hasBlockComments, starts(characters, at: index, with: "/*") {
                flushPlain()
                let start = index
                index += 2
                isInsideBlockComment = consumeBlockComment(characters, from: &index)
                result += token(String(characters[start..<index]), colour: DS.Code.comment)
                continue
            }

            if syntax.lineCommentMarkers.contains(where: { starts(characters, at: index, with: $0) }) {
                flushPlain()
                result += token(String(characters[index...]), colour: DS.Code.comment)
                index = characters.count
                continue
            }

            if syntax.stringDelimiters.contains(characters[index]) {
                flushPlain()
                let start = index
                consumeString(characters, from: &index)
                result += token(String(characters[start..<index]), colour: DS.Code.string)
                continue
            }

            plain.append(characters[index])
            index += 1
        }

        flushPlain()
        return result
    }

    /// Advances past a string literal, and past the line if it is unterminated
    /// — which mid-stream it very often is.
    private static func consumeString(_ characters: [Character], from index: inout Int) {
        let delimiter = characters[index]
        index += 1

        while index < characters.count {
            if characters[index] == "\\" {
                index = min(index + 2, characters.count)
                continue
            }
            if characters[index] == delimiter {
                index += 1
                return
            }
            index += 1
        }
    }

    /// Advances to just past `*/`. Returns whether the comment is still open,
    /// meaning the next line starts inside it.
    private static func consumeBlockComment(_ characters: [Character], from index: inout Int) -> Bool {
        while index < characters.count {
            if starts(characters, at: index, with: "*/") {
                index += 2
                return false
            }
            index += 1
        }
        return true
    }

    private static func starts(_ characters: [Character], at index: Int, with marker: String) -> Bool {
        let marker = Array(marker)
        guard index + marker.count <= characters.count else { return false }
        return Array(characters[index..<(index + marker.count)]) == marker
    }

    /// Splits an ordinary run of code into identifiers and everything else.
    private static func words(in text: String, syntax: Syntax) -> AttributedString {
        var result = AttributedString()
        var word = ""

        func flushWord() {
            guard !word.isEmpty else { return }
            result += token(word, colour: colour(of: word, syntax: syntax))
            word = ""
        }

        for character in text {
            if character.isLetter || character.isNumber || character == "_" || character == "$" {
                word.append(character)
            } else {
                flushWord()
                result += token(String(character), colour: DS.Code.punctuation)
            }
        }

        flushWord()
        return result
    }

    private static func colour(of word: String, syntax: Syntax) -> Color? {
        if syntax.keywords.contains(word) { return DS.Code.keyword }
        if word.first?.isNumber == true { return DS.Code.number }
        // A leading capital is what a type looks like in every language here.
        // Wrong for a shouty constant, which is a colour and not a claim.
        if word.first?.isUppercase == true { return DS.Code.type }
        return nil
    }

    private static func token(_ text: String, colour: Color?) -> AttributedString {
        var attributed = AttributedString(text)
        if let colour { attributed.foregroundColor = colour }
        return attributed
    }
}

private extension CodeHighlighter {
    /// The lexical rules for one language.
    ///
    /// The keyword lists are short on purpose. They exist to make structure
    /// visible at a glance, not to be exhaustive, and a missing keyword renders
    /// as ordinary text rather than as anything wrong.
    nonisolated struct Syntax {
        let keywords: Set<String>
        let lineCommentMarkers: [String]
        let hasBlockComments: Bool
        let stringDelimiters: Set<Character>

        static func named(_ language: String?) -> Syntax {
            switch language ?? "" {
            case "swift":
                Syntax(keywords: swift,
                       lineCommentMarkers: ["//"],
                       hasBlockComments: true,
                       stringDelimiters: ["\""])
            case "python", "py":
                Syntax(keywords: python,
                       lineCommentMarkers: ["#"],
                       hasBlockComments: false,
                       stringDelimiters: ["\"", "'"])
            case "javascript", "js", "typescript", "ts", "jsx", "tsx":
                Syntax(keywords: javascript,
                       lineCommentMarkers: ["//"],
                       hasBlockComments: true,
                       stringDelimiters: ["\"", "'", "`"])
            case "bash", "sh", "shell", "zsh", "console":
                Syntax(keywords: shell,
                       lineCommentMarkers: ["#"],
                       hasBlockComments: false,
                       stringDelimiters: ["\"", "'"])
            case "json":
                // No keywords worth the name and no comments, so this is really
                // just "colour the strings", which is most of what JSON is.
                Syntax(keywords: ["true", "false", "null"],
                       lineCommentMarkers: [],
                       hasBlockComments: false,
                       stringDelimiters: ["\""])
            default:
                // A bare fence is the common case — models omit the language
                // more often than not — so the fallback covers the C-family
                // punctuation that nearly every language on screen will use.
                Syntax(keywords: swift.union(javascript).union(python),
                       lineCommentMarkers: ["//", "#"],
                       hasBlockComments: true,
                       stringDelimiters: ["\"", "'"])
            }
        }

        private static let swift: Set<String> = [
            "actor", "as", "async", "await", "break", "case", "catch", "class", "continue",
            "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough",
            "false", "for", "func", "guard", "if", "import", "in", "init", "internal", "is",
            "let", "nil", "nonisolated", "private", "protocol", "public", "repeat", "return",
            "self", "static", "struct", "subscript", "super", "switch", "throw", "throws",
            "true", "try", "typealias", "var", "where", "while",
        ]

        private static let python: Set<String> = [
            "and", "as", "assert", "async", "await", "break", "class", "continue", "def",
            "del", "elif", "else", "except", "False", "finally", "for", "from", "global",
            "if", "import", "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass",
            "raise", "return", "True", "try", "while", "with", "yield",
        ]

        private static let javascript: Set<String> = [
            "async", "await", "break", "case", "catch", "class", "const", "continue",
            "default", "delete", "do", "else", "export", "extends", "false", "finally",
            "for", "from", "function", "if", "import", "in", "instanceof", "interface",
            "let", "new", "null", "of", "return", "static", "switch", "this", "throw",
            "true", "try", "type", "typeof", "undefined", "var", "void", "while", "yield",
        ]

        private static let shell: Set<String> = [
            "case", "cd", "do", "done", "echo", "elif", "else", "esac", "exit", "export",
            "fi", "for", "function", "if", "in", "local", "return", "source", "then",
            "while",
        ]
    }
}

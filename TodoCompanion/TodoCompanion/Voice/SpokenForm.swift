import Foundation

/// Text rewritten into what Kokoro should actually say, with a way back.
///
/// Kokoro's phonemizer reads any run of letters as a word, so "LRU" came out as
/// "Leku" and `LRUCache` as one unpronounceable blur — in a teaching voice, on
/// exactly the terms the lesson is about. Acronyms are therefore spelled out
/// in letter names, identifiers are split at their capitals, and `O(n)` is
/// said the way people say it.
///
/// The rewrite happens inside the Kokoro synthesizer rather than in
/// `SpeechPlayback.speakable`, because everything upstream — the lesson's
/// label matching, the clause being reported as heard — compares against the
/// text as written. `originalOffset` maps each spoken character back to the
/// written one it came from, so a word cue still lands on the right label.
nonisolated struct SpokenForm: Equatable, Sendable {
    let text: String
    /// For each character of `text`, the index of the written character it
    /// was produced from.
    let originalOffset: [Int]

    /// Said as words, not letters, by anyone who uses them.
    static let wordAcronyms: [String: String] = [
        "JSON": "jason", "NASA": "nasa", "RAM": "ram", "ROM": "rom", "GIF": "gif",
        "YAML": "yammel", "ASCII": "askee", "OK": "okay", "SIM": "sim", "LAN": "lan",
        "WAN": "wan", "CRUD": "crud", "DAG": "dag", "REST": "rest", "SaaS": "sass",
    ]

    /// Ordinary words a model capitalises for emphasis or prints as code
    /// keywords. Spelling these out — "en oh tee" for NOT — is worse than the
    /// problem this type solves.
    static let shoutedWords: Set<String> = [
        "NOT", "NO", "ALL", "ONLY", "NEVER", "ONE", "AND", "OR", "IS", "THE", "MUST",
        "BEFORE", "AFTER", "ALWAYS", "DO", "IT", "IF", "TO", "OF", "IN", "ON", "AT", "BE",
        "WE", "GET", "PUT", "POST", "SET", "NEW", "TRUE", "FALSE", "NULL", "NONE", "YES",
        "NOTE", "WHY", "HOW", "WHAT", "KEY", "VALUE", "HEAD", "TAIL", "MAX", "MIN", "END",
        "STOP", "START", "DONE", "ERROR", "WARNING", "TODO", "FIX", "DELETE", "SELECT",
        "FROM", "WHERE", "JOIN", "INSERT", "UPDATE", "CREATE", "TABLE", "INTO", "BY",
    ]

    static let letterNames: [Character: String] = [
        "A": "ay", "B": "bee", "C": "see", "D": "dee", "E": "ee", "F": "eff", "G": "jee",
        "H": "aitch", "I": "eye", "J": "jay", "K": "kay", "L": "el", "M": "em", "N": "en",
        "O": "oh", "P": "pee", "Q": "cue", "R": "ar", "S": "ess", "T": "tee", "U": "you",
        "V": "vee", "W": "double you", "X": "ex", "Y": "why", "Z": "zee",
    ]

    static func of(_ written: String) -> SpokenForm {
        let characters = Array(written)
        var output = ""
        var offsets: [Int] = []

        func emit(_ text: String, from origin: Int) {
            output += text
            offsets += Array(repeating: origin, count: text.count)
        }

        var index = 0
        while index < characters.count {
            let character = characters[index]

            // "O(n)" → "big O of n". Only a standalone capital O directly
            // followed by a bracket, so "O(" inside a word is left alone.
            if character == "O", index + 1 < characters.count, characters[index + 1] == "(",
               index == 0 || !characters[index - 1].isLetter {
                emit("big O of ", from: index)
                index += 2
                continue
            }

            if let (abbreviation, said) = abbreviations.first(where: { starts(with: $0.0, at: index, in: characters) }) {
                emit(said, from: index)
                index += abbreviation.count
                continue
            }

            guard character.isLetter else {
                emit(String(character), from: index)
                index += 1
                continue
            }

            // An apostrophe between letters is part of the word, or the "s" of
            // "it's" would be a stray letter and come out as "ess".
            var end = index
            while end < characters.count,
                  characters[end].isLetter
                    || ("'’".contains(characters[end]) && end + 1 < characters.count && characters[end + 1].isLetter) {
                end += 1
            }
            let word = String(characters[index..<end])
            for (part, start) in parts(of: word) {
                if start > 0 { emit(" ", from: index + start) }
                emit(spoken(part), from: index + start)
            }
            index = end
        }
        return SpokenForm(text: output, originalOffset: offsets)
    }

    /// Latin shorthand a model writes in prose, which would otherwise be read
    /// as two stray letters.
    static let abbreviations: [(String, String)] = [("e.g.", "for example"), ("i.e.", "that is")]

    private static func starts(with prefix: String, at index: Int, in characters: [Character]) -> Bool {
        let wanted = Array(prefix)
        guard index + wanted.count <= characters.count,
              index == 0 || !characters[index - 1].isLetter
        else { return false }
        return zip(characters[index..<(index + wanted.count)], wanted)
            .allSatisfy { $0.lowercased() == $1.lowercased() }
    }

    /// The written offset a spoken offset came from.
    func writtenOffset(_ spoken: Int) -> Int {
        guard !originalOffset.isEmpty else { return spoken }
        return originalOffset[min(max(0, spoken), originalOffset.count - 1)]
    }

    /// A run of letters split where a reader would hear a new word: `LRUCache`
    /// is `LRU` + `Cache`, `getValue` is `get` + `Value`, `lRUCache` is `l` +
    /// `RU` + `Cache`. A plural acronym keeps its `s` — `APIs`, `URLs`.
    static func parts(of word: String) -> [(String, Int)] {
        let letters = Array(word)
        var parts: [(String, Int)] = []
        var start = 0
        var index = 1
        while index < letters.count {
            let previous = letters[index - 1], current = letters[index]
            let next = index + 1 < letters.count ? letters[index + 1] : nil
            let lowerToUpper = previous.isLowercase && current.isUppercase
            let acronymToWord = previous.isUppercase && current.isUppercase
                && (next?.isLowercase ?? false)
                && !(next == "s" && index + 2 == letters.count)
            if lowerToUpper || acronymToWord {
                parts.append((String(letters[start..<index]), start))
                start = index
            }
            index += 1
        }
        parts.append((String(letters[start...]), start))
        return parts
    }

    /// One part, as it should be said.
    static func spoken(_ part: String) -> String {
        if let word = wordAcronyms[part] { return word }
        if shoutedWords.contains(part) { return part.lowercased() }
        let letters = Array(part)
        let pluralAcronym = letters.count >= 3 && letters.last == "s"
            && letters.dropLast().allSatisfy(\.isUppercase)
        let stem = pluralAcronym ? Array(letters.dropLast()) : letters

        let isAcronym = stem.count >= 2 && stem.count <= 6 && stem.allSatisfy(\.isUppercase)
        // A lone lowercase letter inside an identifier ("l" in lRUCache) is a
        // letter too; a lone word "a" or "I" in a sentence is not split here.
        let isStrayLetter = part.count == 1 && part.first!.isLowercase && part != "a"
        guard isAcronym || isStrayLetter else { return part }

        let names = stem.compactMap { letterNames[Character($0.uppercased())] }
        guard names.count == stem.count else { return part }
        return names.joined(separator: " ") + (pluralAcronym ? "s" : "")
    }
}

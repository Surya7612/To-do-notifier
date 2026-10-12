import Foundation

/// When each word of a synthesized sentence is heard, so a box can move on the
/// word being said rather than once per sentence.
///
/// Kokoro reports how many acoustic frames it gave each phoneme token, which is
/// the same alignment it renders from, so the times are the model's own rather
/// than an estimate laid over the audio. Pure, so it is testable without the
/// model.
nonisolated enum WordTiming {
    /// A word of the sentence as written, and when it starts being heard,
    /// in seconds from the start of that sentence's audio.
    struct Cue: Equatable, Sendable {
        let characterOffset: Int
        let seconds: Double
    }

    /// When each word of `text` starts, from Kokoro's phoneme string and
    /// per-token durations.
    ///
    /// `durations` carries a beginning and an end token around the phonemes.
    /// A phoneme the vocabulary lacks is dropped before synthesis, which breaks
    /// the one-to-one line-up with the string; then the words are spaced by
    /// their length instead, which is coarser but still lands on the right
    /// part of the sentence.
    ///
    /// Written words and spoken words do not pair up exactly — "put(1, 1)" is
    /// one written word and three spoken ones — so written word *i* takes the
    /// spoken word the same fraction of the way through.
    static func cues(text: String,
                     phonemes: String,
                     durations: [Int32],
                     totalSeconds: Double) -> [Cue] {
        let written = wordOffsets(in: text)
        guard !written.isEmpty, totalSeconds > 0 else { return [] }

        let spoken = spokenWordStarts(phonemes: phonemes, durations: durations, totalSeconds: totalSeconds)
            ?? written.map { totalSeconds * Double($0) / Double(max(text.count, 1)) }
        guard !spoken.isEmpty else { return [] }

        return written.enumerated().map { index, offset in
            let target = min(spoken.count - 1, index * spoken.count / written.count)
            return Cue(characterOffset: offset, seconds: spoken[target])
        }
    }

    /// Character offsets at which each whitespace-separated word begins.
    static func wordOffsets(in text: String) -> [Int] {
        var offsets: [Int] = []
        var previousWasSpace = true
        for (offset, character) in text.enumerated() {
            if character.isWhitespace {
                previousWasSpace = true
            } else {
                if previousWasSpace { offsets.append(offset) }
                previousWasSpace = false
            }
        }
        return offsets
    }

    private static func spokenWordStarts(phonemes: String,
                                         durations: [Int32],
                                         totalSeconds: Double) -> [Double]? {
        let characters = Array(phonemes)
        guard durations.count == characters.count + 2 else { return nil }
        let totalUnits = durations.reduce(0) { $0 + Double(max($1, 0)) }
        guard totalUnits > 0 else { return nil }
        let secondsPerUnit = totalSeconds / totalUnits

        var starts: [Double] = []
        var elapsed = Double(max(durations[0], 0))
        var atWordStart = true
        for (index, character) in characters.enumerated() {
            if character == " " {
                atWordStart = true
            } else if atWordStart {
                starts.append(elapsed * secondsPerUnit)
                atWordStart = false
            }
            elapsed += Double(max(durations[index + 1], 0))
        }
        return starts
    }
}

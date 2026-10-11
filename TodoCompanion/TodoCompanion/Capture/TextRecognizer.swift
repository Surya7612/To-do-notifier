import CoreGraphics
import Foundation
import Vision

/// A word Vision read off the screen, and where it sat.
///
/// `boundingBox` is normalized with the origin at the bottom left, exactly as
/// Vision reports it. That happens to match AppKit's screen space, so placing a
/// highlight needs no vertical flip — unlike cropping, which targets a `CGImage`
/// and does. The two conversions look alike and are not.
nonisolated struct TextRegion: Equatable, Sendable {
    let string: String
    let boundingBox: CGRect
    /// Which recognized line this word came from, so neighbouring words can be
    /// recombined into the multi-word labels interfaces actually use.
    let line: Int
    /// Position within that line, for the same reason.
    let position: Int
}

/// The text of a screen and the position of every word in it.
nonisolated struct RecognizedScreen: Equatable, Sendable {
    var text: String = ""
    var regions: [TextRegion] = []
}

/// On-device OCR so the default path never uploads a screenshot anywhere.
enum TextRecognizer {
    /// Ceiling on per-word box lookups, which cost a Vision call each.
    ///
    /// This runs on every summon and the panel waits for it, so a dense screen
    /// must not turn a fast capture into a slow one. Well past the number of
    /// words any answer would name, and the text itself is unaffected — only
    /// the ability to point at something beyond the cutoff.
    nonisolated static let regionLimit = 1200

    /// How careful Vision should be. Summon uses `.fast` so the panel is ready
    /// to ask; Teach / region use `.accurate` so quoted labels still resolve.
    nonisolated enum Quality: Sendable {
        case fast
        case accurate
    }

    /// - Parameter customWords: project names and on-screen identifiers Vision
    ///   should prefer — the same vocabulary `DictationHints` feeds speech.
    ///   Empty by default so callers that do not have a vocabulary stay cheap.
    /// - Parameter quality: `.fast` for the first grab on summon; `.accurate`
    ///   when boxes and Guided warps depend on the read.
    nonisolated static func recognize(in image: CGImage,
                                      limit: Int = 6000,
                                      customWords: [String] = [],
                                      quality: Quality = .accurate) -> RecognizedScreen {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = quality == .fast ? .fast : .accurate
        // Language correction is expensive and only matters when we need to
        // point; skip it on the summon path.
        request.usesLanguageCorrection = quality == .accurate
        // Small UI chrome (menu items, badges) is exactly what Teach points at;
        // the default floor drops too many of those words.
        request.minimumTextHeight = quality == .fast ? 1.0 / 50.0 : 1.0 / 80.0
        // Latest revision picks up more of the dense UI typefaces Teach quotes;
        // language detection keeps a mixed EN/symbol screen from collapsing
        // identifiers into the wrong script.
        request.revision = VNRecognizeTextRequest.currentRevision
        request.automaticallyDetectsLanguage = quality == .accurate
        if quality == .accurate, !customWords.isEmpty {
            request.customWords = Array(customWords.prefix(100))
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NSLog("[TextRecognizer] \(error.localizedDescription)")
            return RecognizedScreen()
        }

        var lines: [String] = []
        var regions: [TextRegion] = []

        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            if regions.count < regionLimit {
                regions.append(contentsOf: words(in: candidate, line: lines.count))
            }
            lines.append(candidate.string)
        }

        let joined = lines.joined(separator: "\n")
        return RecognizedScreen(text: joined.count > limit ? String(joined.prefix(limit)) : joined,
                                regions: regions)
    }

    /// Per-word boxes, asked of Vision by character range.
    ///
    /// A recognized line is often a strip of unrelated labels — a menu bar comes
    /// back as one line — so the line's own box would cover half the screen to
    /// point at one button.
    private nonisolated static func words(in candidate: VNRecognizedText, line: Int) -> [TextRegion] {
        let string = candidate.string
        var regions: [TextRegion] = []

        for (position, range) in string.wordRanges.enumerated() {
            guard let box = try? candidate.boundingBox(for: range) else { continue }
            regions.append(
                TextRegion(string: String(string[range]),
                           boundingBox: box.boundingBox,
                           line: line,
                           position: position)
            )
        }

        return regions
    }
}

private extension String {
    /// Runs of non-whitespace, as index ranges, because Vision locates a
    /// substring by `Range<String.Index>` rather than by its contents.
    nonisolated var wordRanges: [Range<Index>] {
        var ranges: [Range<Index>] = []
        var start: Index?

        for index in indices {
            if self[index].isWhitespace {
                if let from = start {
                    ranges.append(from..<index)
                    start = nil
                }
            } else if start == nil {
                start = index
            }
        }

        if let from = start { ranges.append(from..<endIndex) }
        return ranges
    }
}

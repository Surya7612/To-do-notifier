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
    nonisolated static func recognize(in image: CGImage, limit: Int = 6000) -> RecognizedScreen {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

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
            regions.append(contentsOf: words(in: candidate, line: lines.count))
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

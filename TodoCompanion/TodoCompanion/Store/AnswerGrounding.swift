import Foundation

/// How an answer is grounded in the screen — stated in the panel so OCR-only
/// guessing is not mistaken for vision.
nonisolated enum AnswerGrounding {
    enum Mode: Equatable {
        /// Screenshot goes with the question (cloud or local VL).
        case seesScreenshot
        /// Model receives OCR text only.
        case ocrOnly
        /// Nothing captured yet.
        case noCapture
    }

    static func mode(hasCapture: Bool, sendsImage: Bool) -> Mode {
        guard hasCapture else { return .noCapture }
        return sendsImage ? .seesScreenshot : .ocrOnly
    }

    static func badgeLabel(for mode: Mode) -> String? {
        switch mode {
        case .noCapture: nil
        case .seesScreenshot: "Sees screen"
        case .ocrOnly: "Text only"
        }
    }

}

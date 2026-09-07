import CoreGraphics
import Foundation
import Vision

/// On-device OCR so the default path never uploads a screenshot anywhere.
enum TextRecognizer {
    nonisolated static func recognize(in image: CGImage, limit: Int = 6000) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            NSLog("[TextRecognizer] \(error.localizedDescription)")
            return ""
        }

        let lines = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        let joined = lines.joined(separator: "\n")
        return joined.count > limit ? String(joined.prefix(limit)) : joined
    }
}

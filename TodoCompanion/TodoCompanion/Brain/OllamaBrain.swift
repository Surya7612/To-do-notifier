import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum BrainError: LocalizedError {
    case unreachable
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .unreachable:
            "Can't reach Ollama. Start it with `ollama serve`, then try again."
        case let .http(code, detail):
            "Ollama returned \(code): \(detail)"
        }
    }
}

/// Streams a reply from a local Ollama model. Text-only models get OCR text;
/// vision models can receive the screenshot itself.
struct OllamaBrain {
    let endpoint: URL
    let model: String

    private static let system = """
    You are a concise desktop companion. You are shown what is currently on the user's screen \
    plus their question. Answer directly in at most four sentences. If the screen does not \
    contain the answer, say so instead of guessing.
    """

    func answerStream(question: String, observation: ScreenObservation?, includeImage: Bool)
        -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var body: [String: Any] = [
                        "model": model,
                        "system": Self.system,
                        "prompt": Self.prompt(question: question,
                                              observation: observation,
                                              includeImage: includeImage),
                        "stream": true,
                    ]
                    if includeImage,
                       let image = observation?.image,
                       let encoded = Self.base64PNG(image) {
                        body["images"] = [encoded]
                    }

                    var request = URLRequest(url: endpoint.appending(path: "api/generate"))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    request.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw BrainError.http(http.statusCode, "check the model name in Settings")
                    }

                    for try await line in bytes.lines {
                        guard let data = line.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                        else { continue }
                        if let chunk = object["response"] as? String, !chunk.isEmpty {
                            continuation.yield(chunk)
                        }
                        if object["done"] as? Bool == true { break }
                    }
                    continuation.finish()
                } catch let error as URLError where error.code == .cannotConnectToHost {
                    continuation.finish(throwing: BrainError.unreachable)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func prompt(question: String,
                               observation: ScreenObservation?,
                               includeImage: Bool) -> String {
        var parts: [String] = []
        if let observation {
            parts.append("Active window: \(observation.contextLabel)")
            if !includeImage, !observation.recognizedText.isEmpty {
                parts.append("Text visible on screen:\n\(observation.recognizedText)")
            }
        }
        parts.append("Question: \(question)")
        return parts.joined(separator: "\n\n")
    }

    private static func base64PNG(_ image: CGImage, maxDimension: CGFloat = 1568) -> String? {
        let resized = downscale(image, maxDimension: maxDimension) ?? image
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, resized, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (data as Data).base64EncodedString()
    }

    private static func downscale(_ image: CGImage, maxDimension: CGFloat) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, maxDimension / max(width, height))
        guard scale < 1 else { return image }

        let newWidth = Int(width * scale)
        let newHeight = Int(height * scale)
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }
}

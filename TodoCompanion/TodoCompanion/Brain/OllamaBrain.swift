import Foundation

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
                       let encoded = ImageCodec.base64PNG(from: image) {
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

    /// One-line gloss stored alongside a saved context. Kept separate from the
    /// user's own stated intent.
    func summarize(intent: String, screenText: String) async throws -> String {
        let prompt = """
        The user saved a screenshot and explained why in their own words.
        Write one short sentence (under 20 words) describing what the screen shows.
        Do not restate their reason and do not add commentary.

        Their reason: \(intent)

        Text on screen:
        \(screenText.prefix(2000))
        """

        var collected = ""
        let stream = answerStream(question: prompt, observation: nil, includeImage: false)
        for try await chunk in stream { collected += chunk }
        return collected.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

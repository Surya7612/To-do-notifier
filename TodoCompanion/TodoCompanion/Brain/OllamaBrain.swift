import Foundation

/// Streams a reply from a local Ollama model. Text-only models get OCR text;
/// vision models can receive the screenshot itself.
struct OllamaBrain: Brain {
    let endpoint: URL
    let model: String

    var label: String { model }
    var leavesTheMachine: Bool { false }

    func answerStream(question: String, context: AskContext) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var body: [String: Any] = [
                        "model": model,
                        "system": Prompt.system,
                        "prompt": Prompt.user(question: question, context: context),
                        "stream": true,
                    ]
                    if context.includeImage,
                       let image = context.observation?.image,
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

    /// One-line gloss stored alongside a saved context. Kept separate from the
    /// user's own stated intent.
    ///
    /// Deliberately lives here rather than on `Brain`: summaries are generated
    /// in the background across everything the user keeps, and that body of
    /// material should never be shipped to a third party. Compressing OCR text
    /// into a sentence is also something a small local model does perfectly
    /// well, so there is no quality argument for sending it anywhere.
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
        let stream = answerStream(question: prompt, context: AskContext())
        for try await chunk in stream { collected += chunk }
        return collected.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

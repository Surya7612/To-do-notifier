import Foundation

/// Streams a reply from Google's Gemini API.
///
/// Questions only — summaries and embeddings stay on `OllamaBrain`. Using this
/// sends the selected screen region off the machine whenever the image goes
/// with the question, which the panel states whenever this brain is active.
struct GeminiBrain: Brain {
    static let keychainAccount = "gemini-api-key"
    static let defaultModel = "gemini-2.5-flash"

    let apiKey: String
    let model: String

    var label: String { model }
    var leavesTheMachine: Bool { true }

    func answerStream(question: String, context: AskContext) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var parts: [[String: Any]] = [
                        ["text": Prompt.user(question: question, context: context)],
                    ]

                    if context.includeImage,
                       let image = context.observation?.image,
                       let encoded = ImageCodec.base64PNG(from: image) {
                        parts.append([
                            "inline_data": [
                                "mime_type": "image/png",
                                "data": encoded,
                            ],
                        ])
                    }

                    let body: [String: Any] = [
                        "system_instruction": [
                            "parts": [["text": Prompt.system(for: context)]],
                        ],
                        "contents": [
                            ["role": "user", "parts": parts],
                        ],
                    ]

                    let encodedModel = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? model
                    var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModel):streamGenerateContent")!
                    components.queryItems = [
                        URLQueryItem(name: "alt", value: "sse"),
                        URLQueryItem(name: "key", value: apiKey),
                    ]

                    var request = URLRequest(url: components.url!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    request.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw BrainError.http(http.statusCode, Self.explain(http.statusCode))
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let candidates = object["candidates"] as? [[String: Any]],
                              let content = candidates.first?["content"] as? [String: Any],
                              let responseParts = content["parts"] as? [[String: Any]]
                        else { continue }

                        for part in responseParts {
                            guard let chunk = part["text"] as? String, !chunk.isEmpty else { continue }
                            continuation.yield(chunk)
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private static func explain(_ status: Int) -> String {
        switch status {
        case 400: "bad request — check the model name in Settings"
        case 401, 403: "the API key was rejected"
        case 404: "no such model — check the model name in Settings"
        case 429: "rate limited, or the account is out of quota"
        default: "Gemini rejected the request"
        }
    }
}

import Foundation

/// Streams a reply from Anthropic's Messages API.
///
/// Questions only — summaries and embeddings stay on `OllamaBrain`. Using this
/// sends the selected screen region off the machine whenever the image goes
/// with the question, which the panel states whenever this brain is active.
struct AnthropicBrain: Brain {
    static let keychainAccount = "anthropic-api-key"
    static let defaultModel = "claude-sonnet-4-5"

    let apiKey: String
    let model: String

    var label: String { model }
    var leavesTheMachine: Bool { true }

    func answerStream(question: String, context: AskContext) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var userContent: [[String: Any]] = [
                        [
                            "type": "text",
                            "text": Prompt.user(question: question, context: context),
                        ],
                    ]

                    if context.includeImage,
                       let image = context.observation?.image,
                       let encoded = ImageCodec.base64PNG(from: image) {
                        userContent.append([
                            "type": "image",
                            "source": [
                                "type": "base64",
                                "media_type": "image/png",
                                "data": encoded,
                            ],
                        ])
                    }

                    let body: [String: Any] = [
                        "model": model,
                        "max_tokens": 4096,
                        "stream": true,
                        "system": Prompt.system(for: context),
                        "messages": [
                            ["role": "user", "content": userContent],
                        ],
                    ]

                    var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                    request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
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
                              let type = object["type"] as? String,
                              type == "content_block_delta",
                              let delta = object["delta"] as? [String: Any],
                              let chunk = delta["text"] as? String,
                              !chunk.isEmpty
                        else { continue }

                        continuation.yield(chunk)
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
        case 401: "the API key was rejected"
        case 404: "no such model — check the model name in Settings"
        case 429: "rate limited, or the account is out of credit"
        default: "Anthropic rejected the request"
        }
    }
}

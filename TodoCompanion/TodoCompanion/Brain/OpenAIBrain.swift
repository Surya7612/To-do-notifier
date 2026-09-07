import Foundation

/// Streams a reply from OpenAI.
///
/// Exists because local vision models are genuinely weak at reading interfaces:
/// asked what was on screen, a local model called an editor displaying a
/// screenshot "a To-Do-Notifier application". Explaining a concept or
/// suggesting a next step depends entirely on that reading being right.
///
/// Using it sends the selected screen region off this machine, which the panel
/// says plainly whenever this brain is active.
struct OpenAIBrain: Brain {
    static let keychainAccount = "openai-api-key"
    static let defaultModel = "gpt-4o-mini"

    let apiKey: String
    let model: String

    var label: String { model }
    var leavesTheMachine: Bool { true }

    func answerStream(question: String, context: AskContext) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var content: [[String: Any]] = [
                        [
                            "type": "text",
                            "text": Prompt.user(question: question, context: context),
                        ],
                    ]

                    if context.includeImage,
                       let image = context.observation?.image,
                       let encoded = ImageCodec.base64PNG(from: image) {
                        content.append([
                            "type": "image_url",
                            "image_url": ["url": "data:image/png;base64,\(encoded)"],
                        ])
                    }

                    let body: [String: Any] = [
                        "model": model,
                        "stream": true,
                        "messages": [
                            ["role": "system", "content": Prompt.system],
                            ["role": "user", "content": content],
                        ],
                    ]

                    var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                    request.httpBody = try JSONSerialization.data(withJSONObject: body)
                    request.timeoutInterval = 120

                    let (bytes, response) = try await URLSession.shared.bytes(for: request)
                    if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                        throw BrainError.http(http.statusCode, Self.explain(http.statusCode))
                    }

                    for try await line in bytes.lines {
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = line.dropFirst(6)
                        if payload == "[DONE]" { break }

                        guard let data = payload.data(using: .utf8),
                              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                              let choices = object["choices"] as? [[String: Any]],
                              let delta = choices.first?["delta"] as? [String: Any],
                              let chunk = delta["content"] as? String,
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
        default: "OpenAI rejected the request"
        }
    }
}

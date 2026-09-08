import CoreGraphics
import Foundation

/// Streams a reply from a local Ollama model. Text-only models get OCR text;
/// vision models can receive the screenshot itself.
struct OllamaBrain: Brain {
    let endpoint: URL
    let model: String

    var label: String { model }
    var leavesTheMachine: Bool { false }

    func answerStream(question: String, context: AskContext) -> AsyncThrowingStream<String, Error> {
        generate(system: Prompt.system(for: context),
                 prompt: Prompt.user(question: question, context: context),
                 image: context.includeImage ? context.observation?.image : nil)
    }

    /// - Parameter system: passed in rather than derived, because summarizing
    ///   must not inherit the conversational persona. A teacher told to explain
    ///   its reasoning and name the next action writes a bad one-line gloss.
    private func generate(system: String,
                          prompt: String,
                          image: CGImage?) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    var body: [String: Any] = [
                        "model": model,
                        "system": system,
                        "prompt": prompt,
                        "stream": true,
                    ]
                    if let image, let encoded = ImageCodec.base64PNG(from: image) {
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
        let stream = generate(system: Prompt.summarySystem, prompt: prompt, image: nil)
        for try await chunk in stream { collected += chunk }
        return collected.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Turns text into a vector for meaning-based matching.
    ///
    /// Off the `Brain` protocol for exactly the reason `summarize` is: this runs
    /// unprompted over everything the user keeps, so it must never reach a
    /// hosted provider. Embedding is also the *worst* thing to export, because
    /// it happens once per save rather than once per question — the volume is
    /// the whole library, not a single deliberate ask.
    ///
    /// - Parameter model: the embedding model, which is a different model from
    ///   the one that answers questions and has to be pulled separately.
    func embed(_ text: String, model embeddingModel: String) async throws -> Embedding {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw EmbeddingError.nothingToEmbed }

        var request = URLRequest(url: endpoint.appending(path: "api/embed"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Long OCR text would otherwise be truncated by the model's context
        // window at an arbitrary point, which changes the vector without saying
        // it did. Cutting it here at least makes the limit ours and consistent.
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": embeddingModel,
            "input": String(trimmed.prefix(4000)),
        ])
        request.timeoutInterval = 60

        let (data, response) = try await withUnreachableMapped {
            try await URLSession.shared.data(for: request)
        }

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            // 404 here means the model is not pulled, which is the overwhelming
            // cause and is fixable by the user, so it says so.
            throw http.statusCode == 404
                ? EmbeddingError.modelNotPulled(embeddingModel)
                : BrainError.http(http.statusCode, "embedding request rejected")
        }

        guard let vector = Self.parseEmbedding(data) else {
            throw EmbeddingError.unusableResponse
        }
        return vector
    }

    /// Accepts both shapes Ollama has used: `/api/embed` returns `embeddings`
    /// as an array of vectors, while older builds' `/api/embeddings` returned a
    /// single `embedding`.
    static func parseEmbedding(_ data: Data) -> Embedding? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let batched = root["embeddings"] as? [[Double]], let first = batched.first {
            return Embedding(first.map(Float.init))
        }
        if let single = root["embedding"] as? [Double] {
            return Embedding(single.map(Float.init))
        }
        return nil
    }

    private func withUnreachableMapped<T>(
        _ work: () async throws -> T
    ) async throws -> T {
        do {
            return try await work()
        } catch let error as URLError where error.code == .cannotConnectToHost {
            throw BrainError.unreachable
        }
    }
}

enum EmbeddingError: LocalizedError, Equatable {
    case nothingToEmbed
    case modelNotPulled(String)
    case unusableResponse

    var errorDescription: String? {
        switch self {
        case .nothingToEmbed:
            "Nothing to embed."
        case let .modelNotPulled(model):
            "Ollama has no model called \(model). Run `ollama pull \(model)`, or change it in Settings."
        case .unusableResponse:
            "Ollama returned no vector for that text."
        }
    }
}

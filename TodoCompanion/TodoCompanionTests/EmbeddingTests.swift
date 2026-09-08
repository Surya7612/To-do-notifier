import Foundation
import Testing
@testable import TodoCompanion

/// Vector arithmetic is the one part of meaning-based matching that can be
/// checked exactly. Everything above it — whether a similarity of 0.6 is
/// "related" — is a judgement about a model's output, so these tests pin the
/// maths and the storage round trip and leave the judgement to the thresholds.
@Suite("Embeddings")
struct EmbeddingTests {
    @Test("a vector is normalized, so only its direction is compared")
    func normalizesOnTheWayIn() throws {
        let short = try #require(Embedding([1, 0, 0]))
        let long = try #require(Embedding([100, 0, 0]))

        // Same direction, wildly different magnitude: identical meaning.
        #expect(try #require(short.similarity(to: long)).isApproximately(1.0))
    }

    @Test("identical text scores one, opposite scores minus one")
    func boundsAreOneAndMinusOne() throws {
        let forward = try #require(Embedding([0.3, 0.4, 0.5]))
        let backward = try #require(Embedding([-0.3, -0.4, -0.5]))

        #expect(try #require(forward.similarity(to: forward)).isApproximately(1.0))
        #expect(try #require(forward.similarity(to: backward)).isApproximately(-1.0))
    }

    @Test("perpendicular vectors score zero")
    func orthogonalIsZero() throws {
        let across = try #require(Embedding([1, 0]))
        let up = try #require(Embedding([0, 1]))

        #expect(try #require(across.similarity(to: up)).isApproximately(0))
    }

    /// A zero vector has no direction. Returning nil rather than scoring it
    /// against everything keeps an absent embedding from looking like a
    /// working comparison that found nothing.
    @Test("a vector with no direction is refused rather than scored")
    func refusesDegenerateVectors() {
        #expect(Embedding([]) == nil)
        #expect(Embedding([0, 0, 0]) == nil)
        #expect(Embedding([.nan, 1]) == nil)
        #expect(Embedding([.infinity, 0]) == nil)
    }

    /// Different dimensions mean a different model, which is not a closer or
    /// further match — it is an incomparable one.
    @Test("vectors from different models do not compare")
    func mismatchedLengthsAreIncomparable() throws {
        let small = try #require(Embedding([1, 0]))
        let large = try #require(Embedding([1, 0, 0]))

        #expect(small.similarity(to: large) == nil)
    }

    @Test("a vector survives being stored and read back")
    func roundTripsThroughData() throws {
        let original = try #require(Embedding([0.11, -0.42, 0.87, 0.05]))
        let restored = try #require(Embedding(data: original.data))

        #expect(try #require(original.similarity(to: restored)).isApproximately(1.0))
        #expect(restored.values.count == original.values.count)
    }

    @Test("a truncated or empty blob does not produce a vector")
    func rejectsUnusableData() {
        #expect(Embedding(data: Data()) == nil)
        // Not a whole number of Float32s, so the store is damaged rather than
        // merely holding a shorter vector.
        #expect(Embedding(data: Data([1, 2, 3])) == nil)
    }

    @Test("a realistic dimension count round trips")
    func handlesRealVectorSize() throws {
        // nomic-embed-text returns 768 dimensions.
        let values = (0..<768).map { Float(sin(Double($0))) }
        let original = try #require(Embedding(values))
        let restored = try #require(Embedding(data: original.data))

        #expect(restored.values.count == 768)
        #expect(try #require(original.similarity(to: restored)).isApproximately(1.0))
    }
}

/// The parser sits between Ollama's JSON and everything above it, and Ollama
/// has shipped two different response shapes for this call.
@Suite("Embedding responses")
struct EmbeddingResponseTests {
    private func parse(_ json: String) -> Embedding? {
        OllamaBrain.parseEmbedding(Data(json.utf8))
    }

    @Test("reads the batched shape returned by /api/embed")
    func readsBatchedShape() throws {
        let vector = try #require(parse(#"{"model":"nomic-embed-text","embeddings":[[1,0,0]]}"#))
        #expect(vector.values.count == 3)
    }

    @Test("reads the single-vector shape older builds returned")
    func readsLegacyShape() throws {
        let vector = try #require(parse(#"{"embedding":[0,1,0]}"#))
        #expect(vector.values.count == 3)
    }

    @Test("an unusable response yields no vector rather than a bad one")
    func rejectsJunk() {
        #expect(parse("not json") == nil)
        #expect(parse("{}") == nil)
        #expect(parse(#"{"embeddings":[]}"#) == nil)
        #expect(parse(#"{"embedding":[]}"#) == nil)
        #expect(parse(#"{"embedding":[0,0,0]}"#) == nil, "no direction")
    }

    @Test("a missing model is reported as something the user can fix")
    func namesTheModelToPull() {
        let message = EmbeddingError.modelNotPulled("nomic-embed-text").errorDescription ?? ""

        #expect(message.contains("ollama pull nomic-embed-text"))
    }
}

extension Double {
    func isApproximately(_ other: Double, tolerance: Double = 1e-5) -> Bool {
        abs(self - other) < tolerance
    }
}

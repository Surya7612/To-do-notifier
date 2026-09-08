import Foundation

/// A vector, and the arithmetic for comparing two of them.
///
/// Kept as a value type with no knowledge of Ollama, SwiftData, or retrieval so
/// the maths can be tested without any of them. Everything here is pure.
///
/// `nonisolated` because the project builds with `SWIFT_DEFAULT_ACTOR_ISOLATION
/// = MainActor`, which would otherwise pin arithmetic to the main actor and
/// make it unusable from the background work that produces it.
nonisolated struct Embedding: Equatable, Sendable {
    /// Normalized on the way in, which makes `similarity` a dot product and
    /// makes two vectors of different magnitude but the same direction compare
    /// as identical — the property we actually want from "close in meaning".
    let values: [Float]

    /// - Returns: nil for an empty vector, or one whose magnitude is zero.
    ///   A zero vector has no direction, so it cannot be similar to anything and
    ///   silently scoring it 0 against everything would look like a working
    ///   comparison rather than an absent one.
    init?(_ raw: [Float]) {
        guard !raw.isEmpty else { return nil }

        let magnitude = sqrt(raw.reduce(Float(0)) { $0 + $1 * $1 })
        guard magnitude.isFinite, magnitude > 0 else { return nil }

        values = raw.map { $0 / magnitude }
    }

    /// Cosine similarity, in `-1...1`. Both sides are already unit length, so
    /// this is the dot product.
    ///
    /// Vectors of different length are a different embedding model, not a
    /// closer or further match, so they compare as nil rather than as zero.
    func similarity(to other: Embedding) -> Double? {
        guard values.count == other.values.count else { return nil }

        let dot = zip(values, other.values).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        return Double(min(1, max(-1, dot)))
    }

    // MARK: Storage

    /// Little-endian `Float32`, which is what `Data(bytes:)` gives on every
    /// platform this ships to. Stored as `Data` rather than `[Float]` because
    /// SwiftData would otherwise persist a few hundred separate values per save.
    var data: Data {
        values.withUnsafeBufferPointer { Data(buffer: $0) }
    }

    init?(data: Data) {
        guard !data.isEmpty, data.count % 4 == 0 else { return nil }

        // Copied through an aligned buffer: `Data` from a SwiftData blob carries
        // no alignment guarantee, and loading Float32 straight out of it is
        // undefined behaviour rather than merely slow.
        var raw = [Float](repeating: 0, count: data.count / 4)
        _ = raw.withUnsafeMutableBytes { data.copyBytes(to: $0) }

        self.init(raw)
    }
}

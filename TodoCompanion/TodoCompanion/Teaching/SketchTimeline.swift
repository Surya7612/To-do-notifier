import Foundation

/// When each stroke of a board frame is drawn, paced against what Max says.
///
/// A frame drawn in a second and a half while the beat takes eight to say is
/// a slide with a flourish, not a sketch: the picture was finished before the
/// voice had named anything in it. So the frame is drawn one thing at a time,
/// over roughly the length of its narration, in the order the narration names
/// things — the box appears as the word for it is heard. There are no word
/// timestamps from the synthesizer, so the position of a mention in the text
/// stands in for its time; at a steady speaking rate the two are close.
///
/// Things already on the board from the previous cut are not redrawn. That is
/// what makes consecutive frames read as one continuous drawing rather than a
/// sequence of slides each wiped and re-sketched from nothing.
///
/// Pure and `nonisolated` so it is tested without a view.
nonisolated enum SketchTimeline: Sendable {
    /// How one shape enters the frame.
    enum Reveal: Equatable, Sendable {
        /// On the board in the previous cut and unchanged — drawn complete.
        case carried
        /// Same thing as before with new words — outline complete, text rewritten.
        case relabel(start: Double, end: Double)
        /// New this cut — drawn by the pen between these fractions.
        case draw(start: Double, end: Double)

        func progress(at fraction: Double) -> Double {
            switch self {
            case .carried:
                return 1
            case let .relabel(start, end), let .draw(start, end):
                guard end > start else { return fraction >= start ? 1 : 0 }
                return min(1, max(0, (fraction - start) / (end - start)))
            }
        }
    }

    /// Roughly how fast the voices here speak, in characters of text a second.
    static let speechCharactersPerSecond = 14.5

    /// One reveal per shape, in the frame's own order.
    static func reveals(for frame: BoardScene.Frame,
                        previous: BoardScene.Frame?,
                        narration: String?) -> [Reveal] {
        let shapes = frame.shapes
        let lowered = narration?.lowercased() ?? ""
        let kinds = shapes.map { carryKind($0, previous: previous) }

        // Order key per shape: where the narration first names it, or its
        // place in the frame when it is never named.
        var keys = [Double](repeating: 0, count: shapes.count)
        var subjectKeys: [String: Double] = [:]
        for (index, shape) in shapes.enumerated() where isPlaced(shape) {
            let fallback = Double(index) / Double(max(shapes.count, 1)) * 0.6
            let key = mentionFraction(of: shape, in: lowered) ?? fallback
            keys[index] = key
            if let id = shape.identifier { subjectKeys[id] = key }
        }
        for (index, shape) in shapes.enumerated() where !isPlaced(shape) {
            switch shape {
            case let .arrow(from, to, _, _), let .line(from, to, _):
                keys[index] = max(endpointKey(from, subjectKeys), endpointKey(to, subjectKeys)) + 0.01
            case let .mark(target, _, _):
                keys[index] = (subjectKeys[target] ?? 0.5) + 0.05
            case let .label(x, y, _, _):
                keys[index] = nearestSubjectKey(x: x, y: y, shapes: shapes, keys: subjectKeys) + 0.005
            case let .text(_, _, text, _):
                keys[index] = mentionFraction(ofText: text, in: lowered) ?? 0.85
            default:
                keys[index] = Double(index) / Double(max(shapes.count, 1))
            }
        }

        let order = shapes.indices.sorted { (keys[$0], $0) < (keys[$1], $1) }
        let total = order.reduce(0.0) { sum, index in
            sum + effectiveWeight(shapes[index], kind: kinds[index])
        }

        var reveals = [Reveal](repeating: .carried, count: shapes.count)
        guard total > 0 else { return reveals }
        var cursor = 0.0
        for index in order {
            let weight = effectiveWeight(shapes[index], kind: kinds[index])
            guard weight > 0 else { continue }
            let start = cursor / total
            // A quarter overlap so the pen lifts into the next stroke rather
            // than pausing on each — the difference between drawing and stamping.
            let end = min(1, (cursor + weight * 1.25) / total)
            reveals[index] = kinds[index] == .relabel
                ? .relabel(start: start, end: end)
                : .draw(start: start, end: end)
            cursor += weight
        }
        return reveals
    }

    /// Seconds to draw this frame. Paced to the narration when there is one,
    /// but never so slowly that one box crawls across a long sentence.
    static func duration(for frame: BoardScene.Frame,
                         previous: BoardScene.Frame?,
                         narration: String?) -> TimeInterval {
        let work = frame.shapes.reduce(0.0) { sum, shape in
            sum + effectiveWeight(shape, kind: carryKind(shape, previous: previous))
        }
        guard work > 0 else { return 0.3 }
        let brisk = max(0.8, work * 0.55)
        guard let narration, !narration.isEmpty else { return brisk }
        let spoken = Double(narration.count) / speechCharactersPerSecond
        let paced = min(spoken * 0.85, work * 1.6)
        return min(16, max(brisk, paced))
    }

    // MARK: - Pieces

    enum CarryKind: Equatable { case fresh, relabel, carried }

    static func carryKind(_ shape: BoardScene.Shape, previous: BoardScene.Frame?) -> CarryKind {
        guard let previous else { return .fresh }
        if previous.shapes.contains(shape) { return .carried }
        guard let id = shape.identifier,
              let old = previous.shapes.first(where: { $0.identifier == id }),
              sameKind(old, shape)
        else { return .fresh }
        return .relabel
    }

    private static func sameKind(_ a: BoardScene.Shape, _ b: BoardScene.Shape) -> Bool {
        switch (a, b) {
        case (.circle, .circle), (.ellipse, .ellipse), (.rect, .rect), (.icon, .icon),
             (.bubble, .bubble), (.array, .array):
            return true
        default:
            return false
        }
    }

    private static func effectiveWeight(_ shape: BoardScene.Shape, kind: CarryKind) -> Double {
        switch kind {
        case .carried: return 0
        case .relabel: return 0.35
        case .fresh: return weight(of: shape)
        }
    }

    static func weight(of shape: BoardScene.Shape) -> Double {
        switch shape {
        case .circle, .ellipse, .rect: return 1.0
        case .icon: return 1.1
        case let .array(_, _, _, _, _, values, _, _, _, _):
            return 0.8 + 0.12 * Double(values.count)
        case .path: return 0.9
        case .bubble: return 0.7
        case .arrow, .line: return 0.5
        case .mark: return 0.45
        case .text: return 0.6
        case .label: return 0.25
        }
    }

    private static func isPlaced(_ shape: BoardScene.Shape) -> Bool {
        switch shape {
        case .circle, .ellipse, .rect, .icon, .array, .bubble, .path: return true
        default: return false
        }
    }

    private static func endpointKey(_ endpoint: BoardScene.Shape.Endpoint,
                                    _ keys: [String: Double]) -> Double {
        if case let .id(name) = endpoint { return keys[name] ?? 0 }
        return 0
    }

    private static func nearestSubjectKey(x: Double, y: Double,
                                          shapes: [BoardScene.Shape],
                                          keys: [String: Double]) -> Double {
        var best: (distance: Double, key: Double)?
        for shape in shapes {
            guard let id = shape.identifier, let key = keys[id], let box = shape.footprint else { continue }
            let dx = x - (box.x + box.w / 2)
            let dy = y - (box.y + box.h / 2)
            let distance = (dx * dx + dy * dy).squareRoot()
            if distance < 0.2, distance < (best?.distance ?? .infinity) {
                best = (distance, key)
            }
        }
        return best?.key ?? 0.3
    }

    /// Where in the narration this shape is first named, as a fraction.
    static func mentionFraction(of shape: BoardScene.Shape, in narration: String) -> Double? {
        guard !narration.isEmpty else { return nil }
        var candidates: [String] = []
        switch shape {
        case let .circle(id, _, _, _, _, label),
             let .ellipse(id, _, _, _, _, _, label),
             let .rect(id, _, _, _, _, _, label):
            candidates = phrases(label) + [id].compactMap { $0 }
        case let .icon(id, _, _, _, _, pictogram, _, label):
            candidates = phrases(label) + [pictogram.rawValue] + [id].compactMap { $0 }
        case let .array(id, _, _, _, _, values, _, _, _, label):
            candidates = phrases(label) + [id].compactMap { $0 } + ["array"] + values.prefix(3).map { $0 }
        case let .bubble(_, _, _, _, _, text, _):
            candidates = phrases(text)
        case let .path(_, _, label):
            candidates = phrases(label)
        default:
            return nil
        }
        return earliest(candidates, in: narration)
    }

    private static func mentionFraction(ofText text: String, in narration: String) -> Double? {
        earliest(phrases(text), in: narration)
    }

    /// The whole label first, then its distinctive words — "big: 1" is heard
    /// as "the big counter", so the word is what matches.
    private static func phrases(_ text: String?) -> [String] {
        guard let text = text?.lowercased().trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { return [] }
        let words = text
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
        return [text] + words
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "with", "that", "this", "from", "into", "then", "true", "false",
    ]

    private static func earliest(_ candidates: [String], in narration: String) -> Double? {
        let length = Double(max(narration.count, 1))
        var best: Int?
        for candidate in candidates where candidate.count >= 3 {
            guard let range = narration.range(of: candidate) else { continue }
            let offset = narration.distance(from: narration.startIndex, to: range.lowerBound)
            if offset < (best ?? .max) { best = offset }
        }
        return best.map { Double($0) / length }
    }
}

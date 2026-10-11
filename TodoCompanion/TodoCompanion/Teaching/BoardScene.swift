import Foundation

/// A diagram Max draws on the teaching grid — its own surface, never over the
/// user's screen.
///
/// Lesson marks annotate what Vision already found. A board invents geometry
/// for a concept that is not printed there (a molecule, a recursion tree, a
/// data-flow sketch). PLAN Phase 11 keeps those apart on purpose: invented
/// coordinates belong here, not on OCR boxes.
///
/// The model emits a closed ` ```board ` fence with JSON. Invalid or incomplete
/// JSON yields nothing — the spoken answer still stands, same refusal rule as
/// `Lesson.from`.
///
/// Foundation-only and `nonisolated`, same footing as `Lesson`. Wire types for
/// JSON live *inside* this type so `InferIsolatedConformances` cannot pin their
/// `Decodable` conformance to the main actor. Colours resolve in `BoardView`.
nonisolated struct BoardScene: Equatable, Sendable {
    var title: String?
    var frames: [Frame]

    struct Frame: Equatable, Sendable {
        /// 1-based lesson step when teaching. Nil for Explain frames shown in order.
        var step: Int?
        var shapes: [Shape]
    }

    /// Concept colours the model may name. Raw hex is refused so Light/Dark
    /// stay coherent and a typo cannot paint invisible ink.
    enum ColorToken: String, Equatable, Sendable, Codable, CaseIterable {
        case oxygen
        case hydrogen
        case carbon
        case nitrogen
        case accent
        case emphasis
        case muted
        case success
        case problem
        case primary

        /// Fallback when the model invents a token — readable, not alarming.
        static func resolve(_ raw: String?) -> ColorToken {
            guard let raw, let token = ColorToken(rawValue: raw.lowercased()) else {
                return .accent
            }
            return token
        }
    }

    enum Shape: Equatable, Sendable {
        case circle(id: String?, x: Double, y: Double, r: Double, color: ColorToken, label: String?)
        case ellipse(id: String?, x: Double, y: Double, w: Double, h: Double, color: ColorToken, label: String?)
        case rect(id: String?, x: Double, y: Double, w: Double, h: Double, color: ColorToken, label: String?)
        /// Sketch object from the curated `BoardPictogram` set (car, person, …).
        case icon(id: String?, x: Double, y: Double, w: Double, h: Double,
                  pictogram: BoardPictogram, color: ColorToken, label: String?)
        /// Dialogue / speech bubble with a short line of talk.
        case bubble(id: String?, x: Double, y: Double, w: Double, h: Double,
                    text: String, color: ColorToken)
        case text(x: Double, y: Double, text: String, color: ColorToken)
        case label(x: Double, y: Double, text: String, color: ColorToken)
        /// `label` is written along the arrow — "calls", "returns 3", "miss".
        case arrow(from: Endpoint, to: Endpoint, color: ColorToken, label: String?)
        case line(from: Endpoint, to: Endpoint, color: ColorToken)
        /// A row of cells — array, string, stack, DP row. `highlight` tints
        /// cells; `pointers` name an index (i, j, lo, hi) under its cell.
        case array(id: String?, x: Double, y: Double, w: Double, h: Double,
                   values: [String], highlight: [Int], pointers: [Pointer],
                   color: ColorToken, label: String?)
        /// A hand mark on something already drawn: ring it, underline it,
        /// strike it out, tick it. Refers to a subject by id.
        case mark(target: String, style: MarkStyle, color: ColorToken)
        /// A freehand curve through points — a trajectory, a growth curve,
        /// the route a request takes.
        case path(points: [Point], color: ColorToken, label: String?)

        enum Endpoint: Equatable, Sendable {
            case point(x: Double, y: Double)
            case id(String)
        }

        struct Pointer: Equatable, Sendable {
            var name: String
            var index: Int
        }

        struct Point: Equatable, Sendable {
            var x: Double
            var y: Double
        }

        enum MarkStyle: String, Equatable, Sendable, CaseIterable {
            case circle
            case underline
            case cross
            case check
            case highlight

            static func resolve(_ raw: String?) -> MarkStyle {
                switch raw?.lowercased() {
                case "underline", "under": return .underline
                case "cross", "strike", "x", "reject": return .cross
                case "check", "tick", "ok": return .check
                case "highlight", "glow", "fill": return .highlight
                default: return .circle
                }
            }
        }

        /// Id this shape can be referred to by (arrows, marks, carry-over).
        var identifier: String? {
            switch self {
            case let .circle(id, _, _, _, _, _),
                 let .ellipse(id, _, _, _, _, _, _),
                 let .rect(id, _, _, _, _, _, _),
                 let .icon(id, _, _, _, _, _, _, _),
                 let .bubble(id, _, _, _, _, _, _),
                 let .array(id, _, _, _, _, _, _, _, _, _):
                return id
            default:
                return nil
            }
        }

        /// Normalized footprint of a shape that occupies space (not links/text).
        var footprint: (x: Double, y: Double, w: Double, h: Double)? {
            switch self {
            case let .circle(_, x, y, r, _, _):
                return (x - r, y - r, r * 2, r * 2)
            case let .ellipse(_, x, y, w, h, _, _),
                 let .rect(_, x, y, w, h, _, _),
                 let .icon(_, x, y, w, h, _, _, _),
                 let .array(_, x, y, w, h, _, _, _, _, _):
                return (x, y, w, h)
            default:
                return nil
            }
        }
    }

    /// Reads a board out of a finished (or mid-stream) answer.
    ///
    /// Only a *closed* `board` fence counts. An open fence mid-stream would
    /// otherwise paint a half-parsed diagram and then jump when the rest arrives.
    static func from(answer: String) -> BoardScene? {
        guard let json = extractBoardJSON(from: answer) else { return nil }
        return decode(json)
    }

    /// Teach needs a usable board. Prefer multi-cut; accept one rich frame so a
    /// missing second cut does not force a full second model round-trip.
    static func storyboard(from answer: String) -> BoardScene? {
        guard let scene = from(answer: answer), scene.isStoryboard else { return nil }
        return scene
    }

    /// Multi-frame, or one frame dense enough to teach without a repair ask.
    var isStoryboard: Bool {
        if frames.count >= 2 { return true }
        guard let only = frames.first else { return false }
        return only.shapes.count >= 4
    }

    /// Frame to show for a 0-based lesson step. Prefers an exact `step` match;
    /// otherwise the frame at that index when steps are omitted.
    func frameIndex(forLessonStep lessonStep: Int) -> Int {
        let oneBased = lessonStep + 1
        if let match = frames.firstIndex(where: { $0.step == oneBased }) {
            return match
        }
        return min(max(lessonStep, 0), max(frames.count - 1, 0))
    }

    /// Next Explain frame while speech advances (clamped).
    func clampedFrameIndex(_ index: Int) -> Int {
        guard !frames.isEmpty else { return 0 }
        return min(max(index, 0), frames.count - 1)
    }

    /// Sketch cleanup: readable nodes, role captions, room for arrows *between*
    /// boxes (never through labels). Pure so tests can pin the layout.
    ///
    /// Models stack overlapping coords and strip meaning into one word; polish
    /// rebuilds a tutor board — role above, value inside, tip on top, optional
    /// detail row — without inventing content the model never wrote.
    func polishedForDisplay() -> BoardScene {
        BoardScene(
            title: title.map(Self.shortTitle),
            frames: frames.map(Self.polishFrame)
        )
    }

    private static func shortTitle(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 44 else { return trimmed }
        return String(trimmed.prefix(41)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private struct PolishedNode: Equatable {
        var id: String
        var role: String?
        var body: String
        var color: ColorToken
    }

    private enum PolishedSubject: Equatable {
        case box(PolishedNode)
        case icon(id: String, pictogram: BoardPictogram, label: String?, color: ColorToken)

        var id: String {
            switch self {
            case let .box(node): return node.id
            case let .icon(id, _, _, _): return id
            }
        }

        var searchText: String {
            switch self {
            case let .box(node):
                return [node.role, node.body].compactMap { $0 }.joined(separator: " ")
            case let .icon(_, pictogram, label, _):
                return [pictogram.rawValue, label].compactMap { $0 }.joined(separator: " ")
            }
        }
    }

    private struct PolishedBubble: Equatable {
        var id: String
        var text: String
        var color: ColorToken
    }

    /// A model that laid out a tree, a cycle or a grid cleanly keeps it — only
    /// overlapping or off-board layouts are rebuilt into rows. Re-laying every
    /// frame into one strip is what made every board look the same.
    private static func polishFrame(_ frame: Frame) -> Frame {
        if hasCleanLayout(frame) { return tidiedInPlace(frame) }
        return relaidOut(frame)
    }

    static func hasCleanLayout(_ frame: Frame) -> Bool {
        let boxes = frame.shapes.compactMap(\.footprint)
        guard !boxes.isEmpty else { return false }
        for box in boxes {
            if box.x < -0.01 || box.y < -0.01 || box.x + box.w > 1.01 || box.y + box.h > 1.01 {
                return false
            }
            if box.w < 0.05 || box.h < 0.04 { return false }
        }
        for i in boxes.indices {
            for j in boxes.indices where j > i {
                let a = boxes[i], b = boxes[j]
                let overlapW = min(a.x + a.w, b.x + b.w) - max(a.x, b.x)
                let overlapH = min(a.y + a.h, b.y + b.h) - max(a.y, b.y)
                guard overlapW > 0, overlapH > 0 else { continue }
                let smaller = min(a.w * a.h, b.w * b.h)
                if overlapW * overlapH > smaller * 0.12 { return false }
            }
        }
        return true
    }

    /// Model coordinates kept; only the words are cleaned.
    private static func tidiedInPlace(_ frame: Frame) -> Frame {
        var shapes: [Shape] = []
        for shape in frame.shapes {
            switch shape {
            case let .rect(id, x, y, w, h, color, label):
                let node = cleanedNode(id: id, label: label, color: color, fallbackIndex: shapes.count)
                shapes.append(.rect(id: id, x: x, y: y, w: w, h: h, color: color, label: node?.body))
                if let role = node?.role {
                    shapes.append(.label(x: x + w / 2, y: max(0.02, y - 0.04), text: role, color: .muted))
                }
            case let .ellipse(id, x, y, w, h, color, label):
                let node = cleanedNode(id: id, label: label, color: color, fallbackIndex: shapes.count)
                shapes.append(.ellipse(id: id, x: x, y: y, w: w, h: h, color: color, label: node?.body))
            case let .circle(id, x, y, r, color, label):
                let node = cleanedNode(id: id, label: label, color: color, fallbackIndex: shapes.count)
                shapes.append(.circle(id: id, x: x, y: y, r: r, color: color, label: node?.body))
            case let .icon(id, x, y, w, h, pictogram, color, label):
                shapes.append(.icon(id: id, x: x, y: y, w: w, h: h, pictogram: pictogram,
                                    color: color, label: nil))
                if let label, let clean = cleanedNode(id: id, label: label, color: color,
                                                      fallbackIndex: 0)?.body {
                    shapes.append(.label(x: x + w / 2, y: min(0.97, y + h + 0.025),
                                         text: clean, color: .muted))
                }
            case let .bubble(id, x, y, w, h, text, color):
                if let clean = cleanedTip(text) {
                    shapes.append(.bubble(id: id, x: x, y: y, w: w, h: h, text: clean, color: color))
                }
            case let .text(x, y, text, color):
                if let clean = cleanedTip(text) {
                    shapes.append(.text(x: x, y: y, text: clean, color: color))
                }
            default:
                shapes.append(shape)
            }
        }
        return Frame(step: frame.step, shapes: shapes)
    }

    private static func relaidOut(_ frame: Frame) -> Frame {
        var subjects: [PolishedSubject] = []
        var bubbles: [PolishedBubble] = []
        var tip: String?
        var extraTips: [String] = []
        var arrows: [(String, String, ColorToken, String?)] = []
        // Arrays, marks, curves and point-to-point links have their own
        // geometry the row layout knows nothing about — carried through.
        var passthrough: [Shape] = []

        for shape in frame.shapes {
            switch shape {
            case let .rect(id, _, _, _, _, color, label):
                if let parsed = cleanedNode(id: id, label: label, color: color, fallbackIndex: subjects.count) {
                    subjects.append(.box(parsed))
                }
            case let .ellipse(id, _, _, _, _, color, label):
                if let parsed = cleanedNode(id: id, label: label, color: color, fallbackIndex: subjects.count) {
                    subjects.append(.box(parsed))
                }
            case let .circle(id, _, _, _, color, label):
                if let parsed = cleanedNode(id: id, label: label, color: color, fallbackIndex: subjects.count) {
                    subjects.append(.box(parsed))
                }
            case let .icon(id, _, _, _, _, pictogram, color, label):
                let clean = label.map { cleanedNode(id: id, label: $0, color: color, fallbackIndex: 0)?.body ?? $0 }
                subjects.append(.icon(id: id ?? "icon\(subjects.count)",
                                      pictogram: pictogram,
                                      label: clean,
                                      color: color))
            case let .bubble(id, _, _, _, _, text, color):
                if let cleaned = cleanedTip(text) {
                    bubbles.append(PolishedBubble(id: id ?? "say\(bubbles.count)",
                                                  text: cleaned, color: color))
                }
            case let .text(_, _, text, _):
                if let cleaned = cleanedTip(text) {
                    if tip == nil { tip = cleaned } else { extraTips.append(cleaned) }
                }
            case let .label(_, _, text, _):
                if tip == nil, let cleaned = cleanedTip(text) { tip = cleaned }
            case let .arrow(from, to, color, label):
                if case let .id(a) = from, case let .id(b) = to {
                    arrows.append((a, b, color, label))
                } else {
                    passthrough.append(shape)
                }
            case .line, .array, .mark, .path:
                passthrough.append(shape)
            }
        }

        // Architecture needs more nodes (client / API / services / store);
        // algorithm beats stay smaller so they do not become slide decks.
        let architecture = looksLikeArchitecture(subjects)
        let subjectCap = architecture ? 7 : 5
        if subjects.count > subjectCap { subjects = Array(subjects.prefix(subjectCap)) }
        if bubbles.count > 2 { bubbles = Array(bubbles.prefix(2)) }
        guard !subjects.isEmpty || !bubbles.isEmpty else { return frame }

        var shapes: [Shape] = []

        if let tip {
            shapes.append(.text(x: 0.5, y: 0.08, text: tip, color: .emphasis))
        }

        // Dialogue sits under the tip, above the scene — comic-panel pacing.
        if bubbles.count == 1 {
            shapes.append(.bubble(id: bubbles[0].id, x: 0.22, y: 0.16, w: 0.56, h: 0.12,
                                  text: bubbles[0].text, color: bubbles[0].color))
        } else if bubbles.count >= 2 {
            shapes.append(.bubble(id: bubbles[0].id, x: 0.06, y: 0.15, w: 0.40, h: 0.12,
                                  text: bubbles[0].text, color: bubbles[0].color))
            shapes.append(.bubble(id: bubbles[1].id, x: 0.54, y: 0.15, w: 0.40, h: 0.12,
                                  text: bubbles[1].text, color: bubbles[1].color))
        }

        let known = Set(subjects.map(\.id))
        let linked = arrows.filter { known.contains($0.0) && known.contains($0.1) }

        if architecture {
            layoutArchitecture(subjects, hasBubbles: !bubbles.isEmpty, into: &shapes)
            if linked.isEmpty {
                appendArchitectureArrows(subjects, into: &shapes)
            } else {
                for (from, to, color, label) in linked {
                    shapes.append(.arrow(from: .id(from), to: .id(to), color: color, label: label))
                }
            }
            if let second = extraTips.first {
                shapes.append(.text(x: 0.5, y: 0.92, text: second, color: .muted))
            }
        } else {
            let hasBubbles = !bubbles.isEmpty
            let flowY = hasBubbles ? 0.42 : (subjects.count > 4 ? 0.34 : 0.40)
            let flow = Array(subjects.prefix(min(4, subjects.count)))
            let detail = Array(subjects.dropFirst(flow.count))
            layoutSubjects(flow, y: flowY, height: 0.20, into: &shapes)
            if !detail.isEmpty {
                layoutSubjects(detail, y: 0.70, height: 0.14, into: &shapes)
            }
            if linked.isEmpty {
                for index in 0..<max(flow.count - 1, 0) {
                    shapes.append(.arrow(from: .id(flow[index].id),
                                         to: .id(flow[index + 1].id),
                                         color: .muted, label: nil))
                }
            } else {
                for (from, to, color, label) in linked {
                    shapes.append(.arrow(from: .id(from), to: .id(to), color: color, label: label))
                }
            }
            if let second = extraTips.first {
                shapes.append(.text(x: 0.5, y: detail.isEmpty ? 0.78 : 0.90,
                                    text: second, color: .muted))
            }
        }

        shapes.append(contentsOf: passthrough)
        return Frame(step: frame.step, shapes: shapes)
    }

    /// Client / edge / data stack — system-design boards, not algorithm strips.
    private static func looksLikeArchitecture(_ subjects: [PolishedSubject]) -> Bool {
        let archIcons: Set<BoardPictogram> = [
            .server, .database, .cloud, .laptop, .phone, .building, .lock, .bridge, .robot,
        ]
        let iconHits = subjects.reduce(into: 0) { count, subject in
            if case let .icon(_, pictogram, _, _) = subject, archIcons.contains(pictogram) {
                count += 1
            }
        }
        if iconHits >= 2 { return true }

        let keywords = [
            "api", "cache", "queue", "client", "service", "gateway", "cdn",
            "worker", "load balancer", "lb", "kafka", "redis", "s3", "rpc",
        ]
        let labeled = subjects.filter { subject in
            let hay = subject.searchText.lowercased()
            return keywords.contains { hay.contains($0) }
        }
        return labeled.count >= 2 && subjects.count >= 3
    }

    private static func layoutArchitecture(_ subjects: [PolishedSubject],
                                           hasBubbles: Bool,
                                           into shapes: inout [Shape]) {
        var tiers: [[PolishedSubject]] = [[], [], []]
        for subject in subjects {
            let tier = min(max(architectureTier(subject), 0), 2)
            tiers[tier].append(subject)
        }
        // Drop empty tiers so two-layer designs are not stretched thin.
        let present = tiers.filter { !$0.isEmpty }
        let top = hasBubbles ? 0.30 : 0.22
        let bottom = 0.78
        let step = present.count > 1 ? (bottom - top) / Double(present.count - 1) : 0
        for (index, row) in present.enumerated() {
            let y = top + Double(index) * step
            layoutSubjects(row, y: y, height: 0.16, into: &shapes)
            // Tier labels read like a design doc: Clients / Services / Data.
            if let name = architectureTierName(for: row) {
                shapes.append(.label(x: 0.04, y: y + 0.02, text: name, color: .muted))
            }
        }
    }

    private static func architectureTier(_ subject: PolishedSubject) -> Int {
        if let fromLabel = architectureTier(fromText: subject.searchText) {
            return fromLabel
        }
        if case let .icon(_, pictogram, _, _) = subject {
            switch pictogram {
            case .person, .people, .phone, .laptop, .car, .bike: return 0
            case .cloud, .building, .server, .robot, .bridge, .mail: return 1
            case .database, .lock, .package, .coin, .box: return 2
            default: return 1
            }
        }
        return 1
    }

    private static func architectureTier(fromText text: String) -> Int? {
        let hay = text.lowercased()
        let client = ["client", "user", "browser", "ios", "android", "mobile", "web"]
        let data = ["db", "database", "cache", "redis", "s3", "store", "queue", "kafka", "sql"]
        let edge = ["api", "gateway", "service", "worker", "cdn", "lb", "balancer", "rpc"]
        if client.contains(where: { hay.contains($0) }) { return 0 }
        if data.contains(where: { hay.contains($0) }) { return 2 }
        if edge.contains(where: { hay.contains($0) }) { return 1 }
        return nil
    }

    private static func architectureTierName(for row: [PolishedSubject]) -> String? {
        guard let first = row.first else { return nil }
        switch architectureTier(first) {
        case 0: return "clients"
        case 2: return "data"
        default: return "services"
        }
    }

    /// Top tier → next tier (fan-in/out), not a left-to-right strip through the stack.
    private static func appendArchitectureArrows(_ subjects: [PolishedSubject],
                                                 into shapes: inout [Shape]) {
        var tiers: [[PolishedSubject]] = [[], [], []]
        for subject in subjects {
            tiers[architectureTier(subject)].append(subject)
        }
        let present = tiers.filter { !$0.isEmpty }
        for index in 0..<max(present.count - 1, 0) {
            let upper = present[index]
            let lower = present[index + 1]
            for (u, subject) in upper.enumerated() {
                let target = lower[min(u, lower.count - 1)]
                shapes.append(.arrow(from: .id(subject.id), to: .id(target.id), color: .muted, label: nil))
            }
        }
    }

    private static func layoutSubjects(_ subjects: [PolishedSubject], y: Double, height: Double,
                                       into shapes: inout [Shape]) {
        guard !subjects.isEmpty else { return }
        let count = Double(subjects.count)
        let nodeWidth = min(0.22, 0.84 / count)
        let gap = max(0.04, (0.92 - nodeWidth * count) / max(count + 1, 1))
        for (index, subject) in subjects.enumerated() {
            let x = 0.04 + gap + Double(index) * (nodeWidth + gap)
            switch subject {
            case let .box(node):
                shapes.append(.rect(id: node.id, x: x, y: y, w: nodeWidth, h: height,
                                    color: node.color, label: node.body))
                if let role = node.role {
                    shapes.append(.label(x: x + nodeWidth / 2, y: y - 0.045,
                                         text: role, color: .muted))
                }
            case let .icon(id, pictogram, label, color):
                // Icons stay nearly square so a car does not stretch into a slab.
                let side = min(nodeWidth, height + 0.04)
                let iconX = x + (nodeWidth - side) / 2
                shapes.append(.icon(id: id, x: iconX, y: y, w: side, h: side,
                                    pictogram: pictogram, color: color, label: nil))
                if let label, !label.isEmpty {
                    shapes.append(.label(x: x + nodeWidth / 2, y: y + side + 0.02,
                                         text: label, color: .muted))
                }
            }
        }
    }

    private static func cleanedNode(id: String?, label: String?, color: ColorToken,
                                    fallbackIndex: Int) -> PolishedNode? {
        guard let raw = label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else { return nil }
        var text = raw
            .replacingOccurrences(of: "[index]", with: "i", options: .caseInsensitive)
            .replacingOccurrences(of: "[…]", with: "")
            .replacingOccurrences(of: "...", with: "")
        var role: String?
        if let colon = text.firstIndex(of: ":"),
           text.distance(from: text.startIndex, to: colon) <= 14 {
            let head = String(text[..<colon]).trimmingCharacters(in: .whitespaces)
            let rest = text[text.index(after: colon)...]
                .trimmingCharacters(in: .whitespaces)
            if !head.isEmpty, !rest.isEmpty {
                role = String(head.prefix(12))
                text = rest
            }
        }
        text = text.replacingOccurrences(of: " at ", with: " @ ")
        let words = text.split(whereSeparator: \.isWhitespace)
        if words.count > 5 {
            text = words.prefix(5).joined(separator: " ")
        }
        if text.count > 28 {
            text = String(text.prefix(26)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return PolishedNode(id: id ?? "n\(fallbackIndex)", role: role, body: text, color: color)
    }

    private static func cleanedTip(_ raw: String) -> String? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let words = text.split(whereSeparator: \.isWhitespace)
        if words.count > 12 {
            text = words.prefix(12).joined(separator: " ") + "…"
        } else if text.count > 64 {
            text = String(text.prefix(61)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return text
    }

    /// Contents of the last closed ```board fence, or nil.
    static func extractBoardJSON(from answer: String) -> String? {
        let lines = answer.components(separatedBy: .newlines)
        var blocks: [(lang: String, body: [String])] = []
        var currentLang: String?
        var currentBody: [String]?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") {
                if currentBody != nil {
                    blocks.append((currentLang ?? "", currentBody!))
                    currentLang = nil
                    currentBody = nil
                } else {
                    let lang = String(trimmed.dropFirst(3))
                        .trimmingCharacters(in: .whitespaces)
                        .lowercased()
                    currentLang = lang
                    currentBody = []
                }
            } else {
                currentBody?.append(line)
            }
        }

        guard let board = blocks.last(where: { $0.lang == "board" || $0.lang.hasPrefix("board") })
        else { return nil }
        let contents = board.body.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return contents.isEmpty ? nil : contents
    }

    static func decode(_ json: String) -> BoardScene? {
        guard let data = json.data(using: .utf8) else { return nil }
        do {
            let raw = try JSONDecoder().decode(RawScene.self, from: data)
            let frames = raw.frames.compactMap(makeFrame(_:))
            guard !frames.isEmpty else { return nil }
            let title = raw.title?.trimmingCharacters(in: .whitespacesAndNewlines)
            return BoardScene(title: title?.isEmpty == true ? nil : title, frames: frames)
        } catch {
            return nil
        }
    }

    private static func makeFrame(_ raw: RawFrame) -> Frame? {
        let shapes = raw.shapes.compactMap(makeShape(_:))
        guard !shapes.isEmpty else { return nil }
        return Frame(step: raw.step, shapes: shapes)
    }

    private static func makeShape(_ raw: RawShape) -> Shape? {
        let color = ColorToken.resolve(raw.color)
        switch raw.type.lowercased() {
        case "circle":
            guard let x = raw.x, let y = raw.y, let r = raw.r, r > 0 else { return nil }
            return .circle(id: raw.id, x: clamp01(x), y: clamp01(y), r: min(r, 0.5),
                           color: color, label: raw.label)
        case "ellipse":
            guard let x = raw.x, let y = raw.y, let w = raw.w, let h = raw.h,
                  w > 0, h > 0 else { return nil }
            return .ellipse(id: raw.id, x: clamp01(x), y: clamp01(y),
                            w: min(w, 1), h: min(h, 1), color: color, label: raw.label)
        case "rect", "rectangle":
            guard let x = raw.x, let y = raw.y, let w = raw.w, let h = raw.h,
                  w > 0, h > 0 else { return nil }
            return .rect(id: raw.id, x: clamp01(x), y: clamp01(y),
                         w: min(w, 1), h: min(h, 1), color: color, label: raw.label)
        case "icon", "pictogram", "object", "sprite":
            guard let pictogram = BoardPictogram.resolve(raw.icon ?? raw.name),
                  let x = raw.x, let y = raw.y else { return nil }
            let w = min(max(raw.w ?? 0.16, 0.08), 0.4)
            let h = min(max(raw.h ?? w, 0.08), 0.4)
            return .icon(id: raw.id, x: clamp01(x), y: clamp01(y), w: w, h: h,
                         pictogram: pictogram, color: color, label: raw.label ?? raw.text)
        case "bubble", "speech", "dialogue", "callout":
            guard let x = raw.x, let y = raw.y,
                  let text = (raw.text ?? raw.label)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            let w = min(max(raw.w ?? 0.36, 0.16), 0.8)
            let h = min(max(raw.h ?? 0.14, 0.08), 0.35)
            return .bubble(id: raw.id, x: clamp01(x), y: clamp01(y), w: w, h: h,
                           text: text, color: color)
        case "text":
            guard let x = raw.x, let y = raw.y,
                  let text = raw.text?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return .text(x: clamp01(x), y: clamp01(y), text: text, color: color)
        case "label":
            guard let x = raw.x, let y = raw.y,
                  let text = (raw.text ?? raw.label)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return nil }
            return .label(x: clamp01(x), y: clamp01(y), text: text, color: color)
        case "arrow":
            guard let from = endpoint(raw, prefix: "from"),
                  let to = endpoint(raw, prefix: "to") else { return nil }
            let label = (raw.label ?? raw.text)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .arrow(from: from, to: to, color: color,
                          label: label?.isEmpty == false ? String(label!.prefix(24)) : nil)
        case "array", "cells", "row", "list", "stack":
            guard let values = raw.values, !values.isEmpty,
                  let x = raw.x, let y = raw.y else { return nil }
            let shown = Array(values.prefix(12)).map { String($0.prefix(6)) }
            let w = min(max(raw.w ?? Double(shown.count) * 0.09, 0.15), 0.96)
            let h = min(max(raw.h ?? 0.09, 0.05), 0.2)
            let pointers = (raw.pointers ?? [:])
                .filter { $0.value >= 0 && $0.value < shown.count }
                .map { Shape.Pointer(name: String($0.key.prefix(6)), index: $0.value) }
                .sorted { ($0.index, $0.name) < ($1.index, $1.name) }
            return .array(id: raw.id, x: clamp01(x), y: clamp01(y), w: w, h: h,
                          values: shown,
                          highlight: (raw.highlight ?? []).filter { $0 >= 0 && $0 < shown.count },
                          pointers: pointers, color: color, label: raw.label)
        case "mark", "highlight", "ring", "underline", "cross", "strike", "check", "tick":
            // `{ "type": "check", "x": …, "y": … }` with nothing to mark is the
            // pictogram, not a mark.
            if raw.target == nil, let x = raw.x, let y = raw.y,
               let pictogram = BoardPictogram.resolve(raw.type) {
                let w = min(max(raw.w ?? 0.16, 0.08), 0.4)
                let h = min(max(raw.h ?? w, 0.08), 0.4)
                return .icon(id: raw.id, x: clamp01(x), y: clamp01(y), w: w, h: h,
                             pictogram: pictogram, color: color, label: raw.label ?? raw.text)
            }
            guard let target = raw.target ?? raw.id ?? raw.to, !target.isEmpty else { return nil }
            let style = Shape.MarkStyle.resolve(raw.style ?? raw.type)
            return .mark(target: target, style: style, color: color)
        case "path", "curve", "freehand", "trajectory":
            let points = (raw.points ?? [])
                .compactMap { pair -> Shape.Point? in
                    guard pair.count >= 2 else { return nil }
                    return Shape.Point(x: clamp01(pair[0]), y: clamp01(pair[1]))
                }
            guard points.count >= 2 else { return nil }
            return .path(points: Array(points.prefix(24)), color: color, label: raw.label ?? raw.text)
        case "line":
            guard let from = endpoint(raw, prefix: "from"),
                  let to = endpoint(raw, prefix: "to") else { return nil }
            return .line(from: from, to: to, color: color)
        default:
            // `{ "type": "car", ... }` is accepted as a shorthand icon.
            if let pictogram = BoardPictogram.resolve(raw.type),
               let x = raw.x, let y = raw.y {
                let w = min(max(raw.w ?? 0.16, 0.08), 0.4)
                let h = min(max(raw.h ?? w, 0.08), 0.4)
                return .icon(id: raw.id, x: clamp01(x), y: clamp01(y), w: w, h: h,
                             pictogram: pictogram, color: color, label: raw.label ?? raw.text)
            }
            return nil
        }
    }

    private static func endpoint(_ raw: RawShape, prefix: String) -> Shape.Endpoint? {
        if prefix == "from" {
            if let id = raw.from, !id.isEmpty { return .id(id) }
            if let x = raw.fromX, let y = raw.fromY { return .point(x: clamp01(x), y: clamp01(y)) }
        } else {
            if let id = raw.to, !id.isEmpty { return .id(id) }
            if let x = raw.toX, let y = raw.toY { return .point(x: clamp01(x), y: clamp01(y)) }
        }
        return nil
    }

    private static func clamp01(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    // MARK: Wire format (nested so Decodable stays nonisolated)

    private struct RawScene: Decodable, Sendable {
        var title: String?
        var frames: [RawFrame]
    }

    private struct RawFrame: Decodable, Sendable {
        var step: Int?
        var shapes: [RawShape]
    }

    /// Every field but `type` is read leniently: a model writing `"label": 3`
    /// or `"values": [2, 7]` loses that one field at worst, never the board.
    private struct RawShape: Decodable, Sendable {
        var type: String
        var id: String?
        var x: Double?
        var y: Double?
        var r: Double?
        var w: Double?
        var h: Double?
        var text: String?
        var label: String?
        var color: String?
        /// Pictogram name for `icon` shapes (`car`, `person`, …).
        var icon: String?
        var name: String?
        var from: String?
        var to: String?
        var fromX: Double?
        var fromY: Double?
        var toX: Double?
        var toY: Double?
        var values: [String]?
        var highlight: [Int]?
        var pointers: [String: Int]?
        var target: String?
        var style: String?
        var points: [[Double]]?

        private enum Keys: String, CodingKey {
            case type, id, x, y, r, w, h, text, label, color, icon, name, from, to
            case fromX, fromY, toX, toY, values, highlight, pointers, target, style, points
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: Keys.self)
            type = try c.decode(String.self, forKey: .type)
            id = Self.string(c, .id)
            x = Self.number(c, .x)
            y = Self.number(c, .y)
            r = Self.number(c, .r)
            w = Self.number(c, .w)
            h = Self.number(c, .h)
            text = Self.string(c, .text)
            label = Self.string(c, .label)
            color = Self.string(c, .color)
            icon = Self.string(c, .icon)
            name = Self.string(c, .name)
            from = Self.string(c, .from)
            to = Self.string(c, .to)
            fromX = Self.number(c, .fromX)
            fromY = Self.number(c, .fromY)
            toX = Self.number(c, .toX)
            toY = Self.number(c, .toY)
            values = (try? c.decodeIfPresent([LooseString].self, forKey: .values))?.map(\.value)
            highlight = (try? c.decodeIfPresent([Int].self, forKey: .highlight))
                ?? (try? c.decodeIfPresent(Int.self, forKey: .highlight)).map { [$0] }
            pointers = try? c.decodeIfPresent([String: Int].self, forKey: .pointers)
            target = Self.string(c, .target)
            style = Self.string(c, .style)
            points = try? c.decodeIfPresent([[Double]].self, forKey: .points)
        }

        private static func string(_ c: KeyedDecodingContainer<Keys>, _ key: Keys) -> String? {
            (try? c.decodeIfPresent(LooseString.self, forKey: key))?.value
        }

        private static func number(_ c: KeyedDecodingContainer<Keys>, _ key: Keys) -> Double? {
            if let value = try? c.decodeIfPresent(Double.self, forKey: key) { return value }
            if let text = try? c.decodeIfPresent(String.self, forKey: key) { return Double(text) }
            return nil
        }
    }

    /// A JSON scalar read as text — `7`, `"7"`, `true` and `null` all land.
    private struct LooseString: Decodable, Sendable {
        var value: String

        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if let text = try? c.decode(String.self) {
                value = text
            } else if let whole = try? c.decode(Int.self) {
                value = String(whole)
            } else if let real = try? c.decode(Double.self) {
                value = String(real)
            } else if let flag = try? c.decode(Bool.self) {
                value = flag ? "true" : "false"
            } else if c.decodeNil() {
                value = "∅"
            } else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "not a scalar")
            }
        }
    }
}

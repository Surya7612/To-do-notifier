import SwiftData
import SwiftUI

/// Draws how what you kept connects up.
///
/// A `Canvas` rather than a stack of SwiftUI views: this renders every node and
/// edge on each frame, and a few hundred `View` instances with their own
/// identity and animation machinery would stutter where an immediate-mode draw
/// does not.
struct GraphView: View {
    let contexts: [SavedContext]
    /// Selecting a node in the graph selects it in the library beside it.
    var onSelectSave: (String) -> Void = { _ in }

    @State private var kinds: Set<ContextGraph.NodeKind> = [.project, .topic, .word, .app]
    @State private var positions: [String: CGPoint] = [:]
    @State private var laidOutFor: CGSize = .zero
    @State private var hovered: String?

    private var graph: ContextGraph.Graph {
        ContextGraph.build(items: contexts.map(\.graphItem), kinds: kinds)
    }

    var body: some View {
        VStack(spacing: 0) {
            controls
            Divider().opacity(DS.Alpha.divider)
            canvas
        }
        .navigationTitle("How this connects")
    }

    private var controls: some View {
        HStack(spacing: DS.Spacing.card) {
            ForEach(ContextGraph.NodeKind.allCases.filter { $0 != .save }) { kind in
                Toggle(isOn: Binding(
                    get: { kinds.contains(kind) },
                    set: { isOn in
                        if isOn { kinds.insert(kind) } else { kinds.remove(kind) }
                        // The graph changed shape, so the old positions describe
                        // a different graph.
                        laidOutFor = .zero
                    }
                )) {
                    Label(kind.label, systemImage: kind.glyph)
                }
                .toggleStyle(.button)
                .controlSize(.small)
            }

            Spacer()

            Text("\(graph.nodes.count) nodes · \(graph.edges.count) links")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(DS.Spacing.card)
    }

    private var canvas: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let current = graph

            Canvas { drawing, _ in
                draw(current, into: &drawing)
            }
            .background(.black.opacity(DS.Alpha.well))
            .onContinuousHover { phase in
                switch phase {
                case let .active(point): hovered = node(at: point, in: current)?.id
                case .ended: hovered = nil
                }
            }
            .onTapGesture { point in
                guard let node = node(at: point, in: current), node.kind == .save else { return }
                onSelectSave(String(node.id.dropFirst("save:".count)))
            }
            // Recomputed only when the canvas resizes or the graph changes,
            // never per frame: the layout is a few hundred iterations over
            // every pair of nodes.
            .task(id: layoutKey(size: size, graph: current)) {
                guard size.width > 0, size.height > 0 else { return }
                positions = GraphLayout.positions(for: current, in: size)
                laidOutFor = size
            }
            .overlay {
                if current.isEmpty {
                    ContentUnavailableView(
                        "Nothing to connect yet",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("Save a few screens with #tags and a project, and the shape of what you work on shows up here.")
                    )
                }
            }
            .overlay(alignment: .bottomLeading) {
                let loose = Self.looseSaves(in: current)
                if loose > 0, !current.isEmpty {
                    Text(loose == 1
                         ? "1 keep shares nothing with the others yet. A #tag or a project when you save connects it."
                         : "\(loose) keeps share nothing with the others yet. A #tag or a project when you save connects them.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.6))
                        .padding(DS.Spacing.card)
                }
            }
        }
    }

    private func layoutKey(size: CGSize, graph: ContextGraph.Graph) -> String {
        "\(Int(size.width))x\(Int(size.height))|\(graph.nodes.count)|\(graph.edges.count)"
    }

    private func draw(_ graph: ContextGraph.Graph, into drawing: inout GraphicsContext) {
        let neighbours = highlightedNeighbours(in: graph)

        for edge in graph.edges {
            guard let from = positions[edge.source], let to = positions[edge.target] else { continue }

            var path = Path()
            path.move(to: from)
            path.addLine(to: to)

            let isLit = hovered != nil
                && (edge.source == hovered || edge.target == hovered)
            drawing.stroke(
                path,
                with: .color(.white.opacity(isLit ? 0.55 : hovered == nil ? 0.16 : 0.05)),
                lineWidth: isLit ? 1.6 : 0.8
            )
        }

        for node in graph.nodes {
            guard let point = positions[node.id] else { continue }

            let radius = self.radius(for: node)
            let dimmed = hovered != nil && !neighbours.contains(node.id)
            let colour = color(for: node.kind).opacity(dimmed ? 0.25 : 1)

            drawing.fill(
                Path(ellipseIn: CGRect(x: point.x - radius, y: point.y - radius,
                                       width: radius * 2, height: radius * 2)),
                with: .color(colour)
            )

            // Labels only where they can be read: everything at once is an
            // unreadable mat of text, so small nodes stay silent until hovered.
            // A small library has room for every label, and there unlabelled
            // dots were the whole problem — nothing said what anything was.
            let roomForAll = graph.nodes.count <= Self.labelEverythingBelow
            let showsLabel = node.id == hovered
                || (hovered == nil && (radius >= 9 || roomForAll))
                || (hovered != nil && roomForAll && neighbours.contains(node.id))
            guard showsLabel else { continue }

            let label = node.id == hovered || node.kind != .save
                ? node.label
                : Self.shortened(node.label)
            drawing.draw(
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9)),
                at: CGPoint(x: point.x, y: point.y + radius + 8),
                anchor: .top
            )
        }
    }

    private static let labelEverythingBelow = 40

    private static func shortened(_ label: String) -> String {
        label.count <= 26 ? label : String(label.prefix(24)).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// Saves joined to nothing but the app they came from — which every save
    /// from that app shares, so it says nothing about how they relate.
    static func looseSaves(in graph: ContextGraph.Graph) -> Int {
        var meaningful: [String: Int] = [:]
        for edge in graph.edges where !edge.target.hasPrefix("app:") {
            meaningful[edge.source, default: 0] += 1
        }
        return graph.nodes.count { $0.kind == .save && meaningful[$0.id] == nil }
    }

    /// The hovered node and everything joined to it, so hovering explains a
    /// connection rather than merely highlighting a dot.
    private func highlightedNeighbours(in graph: ContextGraph.Graph) -> Set<String> {
        guard let hovered else { return [] }

        var result: Set<String> = [hovered]
        for edge in graph.edges {
            if edge.source == hovered { result.insert(edge.target) }
            if edge.target == hovered { result.insert(edge.source) }
        }
        return result
    }

    private func radius(for node: ContextGraph.Node) -> CGFloat {
        // Square-rooted: degree varies over orders of magnitude and a linear
        // radius makes one busy topic swallow the canvas.
        let base: CGFloat = node.kind == .save ? 4 : 6
        return base + sqrt(CGFloat(node.degree)) * 2.4
    }

    private func node(at point: CGPoint, in graph: ContextGraph.Graph) -> ContextGraph.Node? {
        graph.nodes
            .compactMap { node -> (ContextGraph.Node, CGFloat)? in
                guard let position = positions[node.id] else { return nil }
                let distance = hypot(position.x - point.x, position.y - point.y)
                // A little forgiveness, or a 4pt dot is impossible to hit.
                return distance <= radius(for: node) + 6 ? (node, distance) : nil
            }
            .min { $0.1 < $1.1 }?
            .0
    }

    private func color(for kind: ContextGraph.NodeKind) -> Color {
        switch kind {
        case .save: DS.Status.saved
        case .project: DS.Status.ready
        case .topic: DS.Status.listening
        case .word: Color.teal
        case .app: DS.Status.busy
        }
    }
}

extension SavedContext {
    /// Flattened for the graph, which is deliberately kept clear of SwiftData.
    var graphItem: ContextGraph.Item {
        ContextGraph.Item(
            id: reminderIdentifier,
            title: intent.isEmpty ? "Untitled" : intent,
            projectName: project?.name,
            topics: topics,
            appName: sourceApp
        )
    }
}

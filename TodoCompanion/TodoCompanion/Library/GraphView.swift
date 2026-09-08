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

    @State private var kinds: Set<ContextGraph.NodeKind> = [.project, .topic, .app]
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
            let showsLabel = node.id == hovered || (hovered == nil && radius >= 9)
            guard showsLabel else { continue }

            drawing.draw(
                Text(node.label)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.9)),
                at: CGPoint(x: point.x, y: point.y + radius + 8),
                anchor: .top
            )
        }
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

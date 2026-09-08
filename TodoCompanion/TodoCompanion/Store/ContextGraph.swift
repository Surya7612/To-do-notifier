import CoreGraphics
import Foundation

/// The connections between what the user kept, laid out for looking at.
///
/// There is no graph database behind this and there is not going to be. The
/// plan says outright not to introduce Neo4j merely because relationships
/// exist, and the relationships already exist: a save belongs to a project,
/// carries the user's `#tags`, and records the app it came from. A graph store
/// would add a server and a query language without adding a single edge.
///
/// What was actually missing was a way to *see* them, which is this.
///
/// `nonisolated` because it is pure structure over value types; the SwiftData
/// models are flattened into `Item` by the caller so nothing here touches the
/// main actor or the store.
nonisolated enum ContextGraph {
    /// One saved context, reduced to only what the graph draws.
    struct Item: Equatable {
        let id: String
        let title: String
        let projectName: String?
        let topics: [String]
        let appName: String

        init(id: String, title: String, projectName: String? = nil,
             topics: [String] = [], appName: String = "") {
            self.id = id
            self.title = title
            self.projectName = projectName
            self.topics = topics
            self.appName = appName
        }
    }

    enum NodeKind: String, CaseIterable, Identifiable, Sendable {
        case save
        case project
        case topic
        case app

        var id: String { rawValue }

        var label: String {
            switch self {
            case .save: "Saves"
            case .project: "Projects"
            case .topic: "Topics"
            case .app: "Apps"
            }
        }

        var glyph: String {
            switch self {
            case .save: "photo"
            case .project: "folder"
            case .topic: "number"
            case .app: "app.dashed"
            }
        }
    }

    struct Node: Identifiable, Equatable {
        let id: String
        let kind: NodeKind
        let label: String
        /// How many edges touch this node. Drives the drawn radius, so a topic
        /// used across a dozen saves reads as a hub at a glance.
        var degree: Int = 0
    }

    struct Edge: Equatable {
        let source: String
        let target: String
    }

    struct Graph: Equatable {
        var nodes: [Node] = []
        var edges: [Edge] = []

        var isEmpty: Bool { nodes.isEmpty }
    }

    /// Builds the graph from saves, including only the node kinds asked for.
    ///
    /// - Parameter kinds: which sorts of node to include. `.save` is always
    ///   present regardless, because every edge here runs from a save to
    ///   something about it — dropping saves would leave nothing connected.
    static func build(items: [Item], kinds: Set<NodeKind>) -> Graph {
        var nodes: [String: Node] = [:]
        var edges: [Edge] = []

        func add(_ node: Node) {
            if nodes[node.id] == nil { nodes[node.id] = node }
        }

        func connect(_ source: String, _ target: String) {
            edges.append(Edge(source: source, target: target))
            nodes[source]?.degree += 1
            nodes[target]?.degree += 1
        }

        for item in items {
            let saveID = "save:\(item.id)"
            add(Node(id: saveID, kind: .save, label: item.title))

            if kinds.contains(.project), let projectName = item.projectName, !projectName.isEmpty {
                let id = "project:\(projectName)"
                add(Node(id: id, kind: .project, label: projectName))
                connect(saveID, id)
            }

            if kinds.contains(.topic) {
                for topic in Set(item.topics) where !topic.isEmpty {
                    let id = "topic:\(topic)"
                    add(Node(id: id, kind: .topic, label: "#\(topic)"))
                    connect(saveID, id)
                }
            }

            if kinds.contains(.app), !item.appName.isEmpty {
                let id = "app:\(item.appName)"
                add(Node(id: id, kind: .app, label: item.appName))
                connect(saveID, id)
            }
        }

        // Sorted so the layout's initial placement is the same every time the
        // window opens, rather than reshuffling with dictionary order.
        return Graph(nodes: nodes.values.sorted { $0.id < $1.id }, edges: edges)
    }
}

/// Force-directed placement, run to a fixed number of steps.
///
/// Deterministic on purpose: no random seeding, so reopening the window gives
/// the same picture and the user can build a spatial memory of their own
/// material. A physics simulation that settles somewhere new each time looks
/// impressive once and is useless twice.
nonisolated enum GraphLayout {
    /// - Parameter iterations: more is tidier and slower. 300 settles a few
    ///   hundred nodes without a visible pause.
    static func positions(for graph: ContextGraph.Graph,
                          in size: CGSize,
                          iterations: Int = 300) -> [String: CGPoint] {
        let nodes = graph.nodes
        guard !nodes.isEmpty else { return [:] }
        guard nodes.count > 1 else {
            return [nodes[0].id: CGPoint(x: size.width / 2, y: size.height / 2)]
        }

        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let area = size.width * size.height
        // Fruchterman–Reingold's ideal edge length: the side of the square each
        // node would get if the canvas were divided evenly between them.
        let ideal = sqrt(area / CGFloat(nodes.count))

        // Start on a circle rather than at random. Deterministic, and it avoids
        // the degenerate case where two nodes land on the same point and the
        // repulsion term divides by zero.
        var points: [CGPoint] = nodes.enumerated().map { index, _ in
            let angle = 2 * CGFloat.pi * CGFloat(index) / CGFloat(nodes.count)
            let radius = min(size.width, size.height) * 0.35
            return CGPoint(x: center.x + radius * cos(angle),
                           y: center.y + radius * sin(angle))
        }

        var indexOf: [String: Int] = [:]
        for (index, node) in nodes.enumerated() { indexOf[node.id] = index }

        let edges = graph.edges.compactMap { edge -> (Int, Int)? in
            guard let source = indexOf[edge.source], let target = indexOf[edge.target] else { return nil }
            return (source, target)
        }

        // Cooling: large early moves to untangle, small late ones to settle.
        var temperature = min(size.width, size.height) / 10

        for _ in 0..<iterations {
            var displacement = [CGPoint](repeating: .zero, count: nodes.count)

            for i in 0..<nodes.count {
                for j in (i + 1)..<nodes.count {
                    var dx = points[i].x - points[j].x
                    var dy = points[i].y - points[j].y
                    var distance = sqrt(dx * dx + dy * dy)

                    // Two nodes exactly on top of each other have no direction
                    // to separate along, so nudge them onto one.
                    if distance < 0.01 {
                        dx = CGFloat(i % 7) - 3
                        dy = CGFloat(j % 7) - 3
                        distance = max(sqrt(dx * dx + dy * dy), 0.01)
                    }

                    let force = (ideal * ideal) / distance
                    let ux = dx / distance, uy = dy / distance
                    displacement[i].x += ux * force
                    displacement[i].y += uy * force
                    displacement[j].x -= ux * force
                    displacement[j].y -= uy * force
                }
            }

            for (source, target) in edges {
                let dx = points[source].x - points[target].x
                let dy = points[source].y - points[target].y
                let distance = max(sqrt(dx * dx + dy * dy), 0.01)

                let force = (distance * distance) / ideal
                let ux = dx / distance, uy = dy / distance
                displacement[source].x -= ux * force
                displacement[source].y -= uy * force
                displacement[target].x += ux * force
                displacement[target].y += uy * force
            }

            for i in 0..<nodes.count {
                let magnitude = max(sqrt(displacement[i].x * displacement[i].x
                    + displacement[i].y * displacement[i].y), 0.01)
                let step = min(magnitude, temperature)

                points[i].x += displacement[i].x / magnitude * step
                points[i].y += displacement[i].y / magnitude * step

                // Kept inside the canvas with a margin for the node's own
                // radius and label.
                points[i].x = min(max(points[i].x, margin), size.width - margin)
                points[i].y = min(max(points[i].y, margin), size.height - margin)
            }

            temperature = max(temperature * 0.95, 0.5)
        }

        var result: [String: CGPoint] = [:]
        for (index, node) in nodes.enumerated() { result[node.id] = points[index] }
        return result
    }

    static let margin: CGFloat = 40
}

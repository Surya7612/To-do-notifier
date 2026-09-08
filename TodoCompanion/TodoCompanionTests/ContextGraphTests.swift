import CoreGraphics
import Foundation
import Testing
@testable import TodoCompanion

/// The graph is a claim about how the user's material relates. A wrong edge is
/// a wrong claim, and unlike a wrong score it is drawn large enough to believe.
@Suite("Context graph")
struct ContextGraphTests {
    private let all: Set<ContextGraph.NodeKind> = [.project, .topic, .app]

    private func item(_ id: String,
                      project: String? = nil,
                      topics: [String] = [],
                      app: String = "") -> ContextGraph.Item {
        ContextGraph.Item(id: id, title: "save \(id)", projectName: project, topics: topics, appName: app)
    }

    @Test("a save becomes a node even with nothing attached to it")
    func lonelySaveStillAppears() {
        let graph = ContextGraph.build(items: [item("1")], kinds: all)

        #expect(graph.nodes.count == 1)
        #expect(graph.nodes.first?.kind == .save)
        #expect(graph.edges.isEmpty)
    }

    @Test("a save links to its project, topics, and app")
    func buildsEveryEdge() {
        let graph = ContextGraph.build(
            items: [item("1", project: "Engram", topics: ["swift", "ui"], app: "Xcode")],
            kinds: all
        )

        #expect(graph.nodes.count == 5, "one save, one project, two topics, one app")
        #expect(graph.edges.count == 4)
    }

    /// The whole point of drawing this: seeing that two things you kept weeks
    /// apart share a tag.
    @Test("two saves sharing a topic share one topic node")
    func sharedTopicIsOneNode() {
        let graph = ContextGraph.build(
            items: [item("1", topics: ["swift"]), item("2", topics: ["swift"])],
            kinds: all
        )

        let topics = graph.nodes.filter { $0.kind == .topic }
        #expect(topics.count == 1)
        #expect(topics.first?.degree == 2)
    }

    @Test("degree counts every edge that touches a node")
    func degreeCountsEdges() throws {
        let graph = ContextGraph.build(
            items: [item("1", project: "Engram", topics: ["a", "b"], app: "Xcode")],
            kinds: all
        )

        let save = try #require(graph.nodes.first { $0.kind == .save })
        #expect(save.degree == 4)
    }

    @Test("turning a kind off removes its nodes and its edges")
    func kindsFilter() {
        let items = [item("1", project: "Engram", topics: ["swift"], app: "Xcode")]

        let topicsOnly = ContextGraph.build(items: items, kinds: [.topic])
        #expect(topicsOnly.nodes.filter { $0.kind == .project }.isEmpty)
        #expect(topicsOnly.nodes.filter { $0.kind == .app }.isEmpty)
        #expect(topicsOnly.edges.count == 1)
    }

    @Test("saves are always present, since every edge starts at one")
    func savesSurviveEveryFilter() {
        let graph = ContextGraph.build(items: [item("1", project: "Engram")], kinds: [])

        #expect(graph.nodes.count == 1)
        #expect(graph.nodes.first?.kind == .save)
    }

    @Test("empty names do not become nodes")
    func ignoresBlanks() {
        let graph = ContextGraph.build(
            items: [item("1", project: "", topics: ["", "real"], app: "")],
            kinds: all
        )

        #expect(graph.nodes.filter { $0.kind == .project }.isEmpty)
        #expect(graph.nodes.filter { $0.kind == .app }.isEmpty)
        #expect(graph.nodes.filter { $0.kind == .topic }.count == 1)
    }

    /// A tag typed twice in one sentence is still one relationship.
    @Test("a topic repeated on one save produces a single edge")
    func deduplicatesTopicsPerSave() {
        let graph = ContextGraph.build(
            items: [item("1", topics: ["swift", "swift"])],
            kinds: all
        )

        #expect(graph.edges.count == 1)
    }

    @Test("node order is stable, so the picture does not reshuffle")
    func buildIsDeterministic() {
        let items = [
            item("1", project: "Engram", topics: ["a"], app: "Xcode"),
            item("2", project: "Engram", topics: ["b"], app: "Safari"),
        ]

        #expect(ContextGraph.build(items: items, kinds: all).nodes
            == ContextGraph.build(items: items, kinds: all).nodes)
    }
}

/// The layout has no assertable "correct" answer, so these pin the properties
/// that make it usable rather than exact coordinates.
@Suite("Graph layout")
struct GraphLayoutTests {
    private let size = CGSize(width: 800, height: 600)

    private func graph(_ items: [ContextGraph.Item]) -> ContextGraph.Graph {
        ContextGraph.build(items: items, kinds: [.project, .topic, .app])
    }

    @Test("every node is placed")
    func placesEveryNode() {
        let built = graph([
            ContextGraph.Item(id: "1", title: "a", projectName: "P", topics: ["x"], appName: "App"),
            ContextGraph.Item(id: "2", title: "b", projectName: "P", topics: ["y"], appName: "App"),
        ])
        let positions = GraphLayout.positions(for: built, in: size, iterations: 50)

        #expect(positions.count == built.nodes.count)
    }

    @Test("nothing is placed outside the canvas")
    func staysInBounds() {
        let items = (1...20).map {
            ContextGraph.Item(id: "\($0)", title: "s\($0)", projectName: "P", topics: ["t"], appName: "A")
        }
        let positions = GraphLayout.positions(for: graph(items), in: size, iterations: 100)

        for point in positions.values {
            #expect(point.x >= GraphLayout.margin && point.x <= size.width - GraphLayout.margin)
            #expect(point.y >= GraphLayout.margin && point.y <= size.height - GraphLayout.margin)
        }
    }

    /// Reopening the window must give the same picture, or a user cannot build
    /// any spatial memory of their own material.
    @Test("the same graph always lays out the same way")
    func isDeterministic() {
        let built = graph((1...10).map {
            ContextGraph.Item(id: "\($0)", title: "s\($0)", projectName: "P", topics: ["t"], appName: "A")
        })

        let first = GraphLayout.positions(for: built, in: size, iterations: 80)
        let second = GraphLayout.positions(for: built, in: size, iterations: 80)

        for (id, point) in first {
            #expect(second[id]?.x == point.x)
            #expect(second[id]?.y == point.y)
        }
    }

    /// The one thing a force layout is actually for.
    @Test("connected nodes settle closer than unconnected ones")
    func edgesPullThingsTogether() throws {
        // Two clusters that share nothing: A with B, C with D.
        let built = ContextGraph.build(items: [
            ContextGraph.Item(id: "a", title: "a", topics: ["left"]),
            ContextGraph.Item(id: "b", title: "b", topics: ["left"]),
            ContextGraph.Item(id: "c", title: "c", topics: ["right"]),
            ContextGraph.Item(id: "d", title: "d", topics: ["right"]),
        ], kinds: [.topic])

        let positions = GraphLayout.positions(for: built, in: size, iterations: 400)
        func point(_ id: String) throws -> CGPoint { try #require(positions[id]) }

        let aToShared = try hypot(point("save:a").x - point("topic:left").x,
                                  point("save:a").y - point("topic:left").y)
        let aToOther = try hypot(point("save:a").x - point("topic:right").x,
                                 point("save:a").y - point("topic:right").y)

        #expect(aToShared < aToOther)
    }

    @Test("an empty graph lays out to nothing rather than crashing")
    func handlesEmpty() {
        #expect(GraphLayout.positions(for: ContextGraph.Graph(), in: size).isEmpty)
    }

    @Test("a single node is centred")
    func centresLoneNode() {
        let built = graph([ContextGraph.Item(id: "1", title: "only")])
        let positions = GraphLayout.positions(for: built, in: size)

        #expect(positions["save:1"]?.x == size.width / 2)
        #expect(positions["save:1"]?.y == size.height / 2)
    }
}

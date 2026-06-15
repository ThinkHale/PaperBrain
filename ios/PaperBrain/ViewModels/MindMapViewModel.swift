import Foundation
import SwiftUI

// MARK: - Graph models

struct MapNode: Identifiable {
    enum Kind { case note, tag }
    let id: String
    let kind: Kind
    var label: String
    var x: Double
    var y: Double
    var isPinned: Bool = false
    var vx: Double = 0
    var vy: Double = 0
}

struct MapEdge: Identifiable {
    let id: String
    let sourceId: String
    let targetId: String
    let weight: Double
    let isManual: Bool
}

// MARK: - ViewModel

@MainActor
final class MindMapViewModel: ObservableObject {
    @Published var nodes: [MapNode] = []
    @Published var edges: [MapEdge] = []
    @Published var isLoading = false
    @Published var error: String?
    @Published var selectedNodeId: String?
    @Published var tagFilter: String? = nil
    @Published var showTagLinks = true

    // Physics params
    var repulsion: Double = 800
    var springLength: Double = 140
    var springStrength: Double = 0.05
    var damping: Double = 0.85
    var gravity: Double = 0.02

    private let db = SupabaseService.shared
    private var allNotes: [Note] = []

    func load(userId: UUID, notes: [Note]) async {
        isLoading = true
        allNotes = notes
        do {
            let relations = try await db.fetchAllRelations(userId: userId)
            let positions = try await db.fetchMindmapPositions(userId: userId)
            buildGraph(notes: notes, relations: relations, savedPositions: positions)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Graph building

    private func buildGraph(notes: [Note], relations: [Relation], savedPositions: [MindmapPosition]) {
        let posMap = Dictionary(uniqueKeysWithValues: savedPositions.map { ($0.nodeId, $0) })
        var newNodes: [MapNode] = []
        var newEdges: [MapEdge] = []

        // Note nodes
        for note in notes {
            let saved = posMap[note.id.uuidString]
            let angle = Double.random(in: 0..<(2 * .pi))
            let r = Double.random(in: 100...300)
            newNodes.append(MapNode(
                id: note.id.uuidString,
                kind: .note,
                label: note.title,
                x: saved?.x ?? cos(angle) * r,
                y: saved?.y ?? sin(angle) * r,
                isPinned: saved != nil
            ))
        }

        // Tag nodes + note–tag edges
        var allTags: Set<String> = []
        for note in notes { (note.tags ?? []).forEach { allTags.insert($0) } }
        for tag in allTags {
            let saved = posMap["tag:\(tag)"]
            let angle = Double.random(in: 0..<(2 * .pi))
            let r = Double.random(in: 80...200)
            newNodes.append(MapNode(
                id: "tag:\(tag)",
                kind: .tag,
                label: tag,
                x: saved?.x ?? cos(angle) * r,
                y: saved?.y ?? sin(angle) * r,
                isPinned: saved != nil
            ))
            for note in notes where (note.tags ?? []).contains(tag) {
                newEdges.append(MapEdge(
                    id: "\(note.id.uuidString)-tag:\(tag)",
                    sourceId: note.id.uuidString,
                    targetId: "tag:\(tag)",
                    weight: 0.3,
                    isManual: false
                ))
            }
        }

        // Relation edges
        for rel in relations where rel.score >= 0.45 {
            newEdges.append(MapEdge(
                id: rel.id.uuidString,
                sourceId: rel.fromId.uuidString,
                targetId: rel.toId.uuidString,
                weight: rel.score,
                isManual: rel.manual
            ))
        }

        nodes = newNodes
        edges = newEdges
    }

    // MARK: - Force simulation step

    func simulationStep(canvasSize: CGSize) {
        let cx = canvasSize.width / 2
        let cy = canvasSize.height / 2
        let nodeMap = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })

        for i in nodes.indices {
            guard !nodes[i].isPinned else { continue }
            var fx = 0.0, fy = 0.0

            // Gravity toward center
            fx += (cx - nodes[i].x) * gravity
            fy += (cy - nodes[i].y) * gravity

            // Repulsion from other nodes
            for j in nodes.indices where j != i {
                let dx = nodes[i].x - nodes[j].x
                let dy = nodes[i].y - nodes[j].y
                let distSq = max(dx * dx + dy * dy, 1)
                let dist = distSq.squareRoot()
                fx += (dx / dist) * (repulsion / distSq)
                fy += (dy / dist) * (repulsion / distSq)
            }

            // Spring attraction along edges
            for edge in edges {
                let otherId: String?
                if edge.sourceId == nodes[i].id { otherId = edge.targetId }
                else if edge.targetId == nodes[i].id { otherId = edge.sourceId }
                else { continue }

                if let otherId, let j = nodeMap[otherId] {
                    let dx = nodes[j].x - nodes[i].x
                    let dy = nodes[j].y - nodes[i].y
                    let dist = max((dx * dx + dy * dy).squareRoot(), 1)
                    let force = (dist - springLength) * springStrength
                    fx += dx / dist * force
                    fy += dy / dist * force
                }
            }

            nodes[i].vx = (nodes[i].vx + fx) * damping
            nodes[i].vy = (nodes[i].vy + fy) * damping
            nodes[i].x += nodes[i].vx
            nodes[i].y += nodes[i].vy
        }
    }

    // MARK: - Interaction

    func pin(nodeId: String, x: Double, y: Double, userId: UUID) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        nodes[idx].x = x
        nodes[idx].y = y
        nodes[idx].isPinned = true
        Task { try? await db.upsertMindmapPosition(userId: userId, nodeId: nodeId, x: x, y: y) }
    }

    func unpin(nodeId: String) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        nodes[idx].isPinned = false
    }

    var allTags: [String] {
        nodes.filter { $0.kind == .tag }.map { $0.label }.sorted()
    }

    var visibleNodes: [MapNode] {
        guard let filter = tagFilter else { return nodes }
        let tagNodeId = "tag:\(filter)"
        let connectedNoteIds = Set(edges
            .filter { $0.sourceId == tagNodeId || $0.targetId == tagNodeId }
            .flatMap { [$0.sourceId, $0.targetId] })
        return nodes.filter { $0.id == tagNodeId || connectedNoteIds.contains($0.id) }
    }

    var visibleEdges: [MapEdge] {
        let visibleIds = Set(visibleNodes.map { $0.id })
        return edges.filter { edge in
            visibleIds.contains(edge.sourceId) && visibleIds.contains(edge.targetId) &&
            (showTagLinks || (!edge.sourceId.hasPrefix("tag:") && !edge.targetId.hasPrefix("tag:")))
        }
    }
}

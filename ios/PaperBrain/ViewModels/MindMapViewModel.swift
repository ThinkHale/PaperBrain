import Foundation
import SwiftUI

// MARK: - Graph models

struct MapNode: Identifiable {
    enum Kind {
        case note
        case tag
    }

    let id: String
    let kind: Kind
    var label: String
    var subtitle: String?
    var clusterKey: String?       // category this node belongs to (for coloring)
    var x: Double
    var y: Double
    var z: Double
    var radius: Double
    var energy: Double
    var isPinned = false
    var vx: Double = 0
    var vy: Double = 0
    var vz: Double = 0
}

struct MapEdge: Identifiable {
    enum Kind {
        case relation
        case tag
        case sharedTag
    }

    let id: String
    let sourceId: String
    let targetId: String
    let weight: Double
    let kind: Kind
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
    @Published var tagFilter: String?
    @Published var searchQuery = ""
    @Published var showTagLinks = true
    @Published var isFocusMode = true

    private let db = SupabaseService.shared
    private var notesById: [String: Note] = [:]
    private var noteOrder: [String: Int] = [:]
    private var lastRelations: [Relation] = []

    private let repulsion = 3_200.0
    private let tagRepulsion = 1_650.0
    private let springLength = 172.0
    private let springStrength = 0.018
    private let damping = 0.82
    private let gravity = 0.006
    private let depthGravity = 0.018

    func load(userId: UUID, notes: [Note]) async {
        isLoading = true
        error = nil

        do {
            async let relationsTask = db.fetchAllRelations(userId: userId)
            async let positionsTask = db.fetchMindmapPositions(userId: userId)
            let (relations, positions) = try await (relationsTask, positionsTask)
            buildGraph(notes: notes, relations: relations, savedPositions: positions)
        } catch {
            self.error = error.localizedDescription
            buildGraph(notes: notes, relations: [], savedPositions: [])
        }

        isLoading = false
    }

    var selectedNode: MapNode? {
        guard let selectedNodeId else { return nil }
        return nodes.first { $0.id == selectedNodeId }
    }

    var selectedNote: Note? {
        guard let selectedNodeId else { return nil }
        return notesById[selectedNodeId]
    }

    func note(id: String) -> Note? {
        notesById[id]
    }

    var allTags: [String] {
        nodes
            .filter { $0.kind == .tag }
            .map(\.label)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    var visibleNodes: [MapNode] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let tagVisibleIds = idsVisibleForTagFilter()

        if query.isEmpty {
            return nodes.filter { tagVisibleIds.contains($0.id) }
        }

        let matchingIds = Set(nodes.compactMap { node -> String? in
            guard tagVisibleIds.contains(node.id) else { return nil }
            let note = notesById[node.id]
            let haystack = [
                node.label,
                node.subtitle ?? "",
                note?.summary ?? "",
                note?.tags?.joined(separator: " ") ?? "",
                note?.keyPoints?.joined(separator: " ") ?? ""
            ].joined(separator: " ").lowercased()
            return haystack.contains(query) ? node.id : nil
        })

        let neighborIds = idsConnected(to: matchingIds)
        return nodes.filter { matchingIds.contains($0.id) || neighborIds.contains($0.id) }
    }

    var visibleEdges: [MapEdge] {
        let visibleIds = Set(visibleNodes.map(\.id))
        return edges.filter { edge in
            visibleIds.contains(edge.sourceId) &&
            visibleIds.contains(edge.targetId) &&
            (showTagLinks || edge.kind != .tag)
        }
    }

    func isNodeActive(_ node: MapNode) -> Bool {
        guard isFocusMode, let selectedNodeId else { return true }
        return node.id == selectedNodeId || idsConnected(to: [selectedNodeId]).contains(node.id)
    }

    func isEdgeActive(_ edge: MapEdge) -> Bool {
        guard isFocusMode, let selectedNodeId else { return true }
        return edge.sourceId == selectedNodeId || edge.targetId == selectedNodeId
    }

    func select(nodeId: String?) {
        selectedNodeId = nodeId
    }

    func resetLayout() {
        let notes = noteOrder
            .sorted { $0.value < $1.value }
            .compactMap { notesById[$0.key] }
        nodes = []
        buildGraph(notes: notes, relations: lastRelations, savedPositions: [])
    }

    func simulationStep() {
        guard nodes.count > 1 else { return }
        let nodeIndex = Dictionary(uniqueKeysWithValues: nodes.enumerated().map { ($1.id, $0) })

        for i in nodes.indices {
            guard !nodes[i].isPinned else { continue }

            var fx = -nodes[i].x * gravity
            var fy = -nodes[i].y * gravity
            var fz = -nodes[i].z * depthGravity

            for j in nodes.indices where i != j {
                let dx = nodes[i].x - nodes[j].x
                let dy = nodes[i].y - nodes[j].y
                let dz = (nodes[i].z - nodes[j].z) * 0.62
                let distSq = max(dx * dx + dy * dy + dz * dz, 36)
                let dist = sqrt(distSq)
                let baseRepulsion = nodes[i].kind == .tag || nodes[j].kind == .tag ? tagRepulsion : repulsion
                let force = baseRepulsion / distSq
                fx += (dx / dist) * force
                fy += (dy / dist) * force
                fz += (dz / dist) * force * 0.45
            }

            for edge in edges {
                let otherId: String?
                if edge.sourceId == nodes[i].id {
                    otherId = edge.targetId
                } else if edge.targetId == nodes[i].id {
                    otherId = edge.sourceId
                } else {
                    otherId = nil
                }

                guard let otherId, let j = nodeIndex[otherId] else { continue }

                let dx = nodes[j].x - nodes[i].x
                let dy = nodes[j].y - nodes[i].y
                let dz = nodes[j].z - nodes[i].z
                let dist = max(sqrt(dx * dx + dy * dy + dz * dz), 1)
                let desired = springLength * springLengthMultiplier(for: edge)
                let force = (dist - desired) * springStrength * max(0.25, edge.weight)

                fx += dx / dist * force
                fy += dy / dist * force
                fz += dz / dist * force * 0.48
            }

            nodes[i].vx = (nodes[i].vx + fx) * damping
            nodes[i].vy = (nodes[i].vy + fy) * damping
            nodes[i].vz = (nodes[i].vz + fz) * damping
            nodes[i].x += nodes[i].vx
            nodes[i].y += nodes[i].vy
            nodes[i].z = min(260, max(-260, nodes[i].z + nodes[i].vz))
        }
    }

    func pin(nodeId: String, at point: CGPoint, userId: UUID) {
        guard let idx = nodes.firstIndex(where: { $0.id == nodeId }) else { return }
        nodes[idx].x = point.x
        nodes[idx].y = point.y
        nodes[idx].vx = 0
        nodes[idx].vy = 0
        nodes[idx].isPinned = true

        let parts = nodeId.split(separator: ":", maxSplits: 1).map(String.init)
        let nodeType = parts.count == 2 ? parts[0] : "note"
        let rawNodeId = parts.count == 2 ? parts[1] : nodeId

        Task {
            try? await db.upsertMindmapPosition(
                userId: userId,
                nodeType: nodeType,
                nodeId: rawNodeId,
                x: point.x,
                y: point.y
            )
        }
    }

    // MARK: - Graph building

    private func buildGraph(notes: [Note], relations: [Relation], savedPositions: [MindmapPosition]) {
        notesById = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        noteOrder = Dictionary(uniqueKeysWithValues: notes.enumerated().map { ($1.id, $0) })
        lastRelations = relations

        let previousNodes = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let savedPositionMap = Dictionary(uniqueKeysWithValues: savedPositions.map { ("\($0.nodeType):\($0.nodeId)", $0) })
        let noteIds = Set(notes.map(\.id))
        // Cluster on the curated categories ("suns"); fall back to topics for
        // legacy notes that predate categories, so the map is never empty.
        let sortedTags = Array(Set(notes.flatMap { clusterKeys(for: $0) }))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        var nextNodes: [MapNode] = []
        var nextEdges: [MapEdge] = []
        var tagAnchors: [String: CGPoint] = [:]

        for (index, tag) in sortedTags.enumerated() {
            let nodeId = "tag:\(tag)"
            let angle = angleFor(index: index, total: max(sortedTags.count, 1), phase: -0.35)
            let radius = 145.0 + Double(sortedTags.count) * 6.0
            let anchor = CGPoint(x: cos(angle) * radius, y: sin(angle) * radius)
            tagAnchors[tag] = anchor

            nextNodes.append(makeNode(
                id: nodeId,
                kind: .tag,
                label: tag,
                subtitle: "Category",
                clusterKey: tag,
                fallback: anchor,
                z: deterministicDepth(for: nodeId, magnitude: 170),
                radius: 18,
                energy: 0.65,
                previous: previousNodes[nodeId],
                saved: savedPositionMap["tag:\(tag)"]
            ))
        }

        for (index, note) in notes.enumerated() {
            let fallback = fallbackPoint(for: note, index: index, total: max(notes.count, 1), tagAnchors: tagAnchors)
            let relatedCount = relations.filter { $0.fromId == note.id || $0.toId == note.id }.count
            let tagCount = note.tags?.count ?? 0
            let energy = min(1.0, 0.35 + Double(relatedCount) * 0.11 + Double(tagCount) * 0.05)

            nextNodes.append(makeNode(
                id: note.id,
                kind: .note,
                label: note.displayTitle,
                subtitle: note.summary,
                clusterKey: clusterKeys(for: note).first,
                fallback: fallback,
                z: deterministicDepth(for: note.id, magnitude: 220),
                radius: 24 + min(10, Double(relatedCount) * 2.4),
                energy: energy,
                previous: previousNodes[note.id],
                saved: savedPositionMap["note:\(note.id)"]
            ))

            for tag in clusterKeys(for: note) where tagAnchors[tag] != nil {
                nextEdges.append(MapEdge(
                    id: "\(note.id)-tag:\(tag)",
                    sourceId: note.id,
                    targetId: "tag:\(tag)",
                    weight: 0.5,
                    kind: .tag,
                    isManual: false
                ))
            }
        }

        for relation in relations where noteIds.contains(relation.fromId) && noteIds.contains(relation.toId) && relation.score >= 0.35 {
            nextEdges.append(MapEdge(
                id: relation.id,
                sourceId: relation.fromId,
                targetId: relation.toId,
                weight: relation.manual ? 1.0 : relation.score,
                kind: .relation,
                isManual: relation.manual
            ))
        }

        nextEdges.append(contentsOf: sharedTagEdges(notes: notes))

        nodes = nextNodes
        edges = uniquedEdges(nextEdges)
        if let selectedNodeId, !nodes.contains(where: { $0.id == selectedNodeId }) {
            self.selectedNodeId = nil
        }
    }

    private func makeNode(
        id: String,
        kind: MapNode.Kind,
        label: String,
        subtitle: String?,
        clusterKey: String?,
        fallback: CGPoint,
        z: Double,
        radius: Double,
        energy: Double,
        previous: MapNode?,
        saved: MindmapPosition?
    ) -> MapNode {
        if var previous {
            previous.label = label
            previous.subtitle = subtitle
            previous.clusterKey = clusterKey
            previous.radius = radius
            previous.energy = energy
            return previous
        }

        return MapNode(
            id: id,
            kind: kind,
            label: label,
            subtitle: subtitle,
            clusterKey: clusterKey,
            x: saved?.x ?? fallback.x,
            y: saved?.y ?? fallback.y,
            z: z,
            radius: radius,
            energy: energy,
            isPinned: saved != nil
        )
    }

    /// The keys a note clusters under: its curated categories, or its topic tags
    /// for older notes that have no categories yet.
    private func clusterKeys(for note: Note) -> [String] {
        let cats = note.categories ?? []
        return cats.isEmpty ? (note.tags ?? []) : cats
    }

    private func fallbackPoint(for note: Note, index: Int, total: Int, tagAnchors: [String: CGPoint]) -> CGPoint {
        let anchors = clusterKeys(for: note).compactMap { tagAnchors[$0] }
        let jitter = jitterPoint(for: note.id, radius: 86)

        if !anchors.isEmpty {
            let centerX = anchors.map(\.x).reduce(0, +) / CGFloat(anchors.count)
            let centerY = anchors.map(\.y).reduce(0, +) / CGFloat(anchors.count)
            return CGPoint(x: centerX + jitter.x, y: centerY + jitter.y)
        }

        let angle = angleFor(index: index, total: total, phase: 0.55)
        let radius = 210.0 + Double(index % 5) * 34.0
        return CGPoint(x: cos(angle) * radius + jitter.x * 0.45, y: sin(angle) * radius + jitter.y * 0.45)
    }

    private func sharedTagEdges(notes: [Note]) -> [MapEdge] {
        var result: [MapEdge] = []
        let taggedNotes = notes.map { ($0.id, Set(clusterKeys(for: $0))) }

        for i in taggedNotes.indices {
            for j in taggedNotes.indices where j > i {
                let shared = taggedNotes[i].1.intersection(taggedNotes[j].1)
                guard shared.count >= 2 else { continue }
                result.append(MapEdge(
                    id: "shared:\(taggedNotes[i].0):\(taggedNotes[j].0)",
                    sourceId: taggedNotes[i].0,
                    targetId: taggedNotes[j].0,
                    weight: min(0.62, 0.18 + Double(shared.count) * 0.1),
                    kind: .sharedTag,
                    isManual: false
                ))
            }
        }

        return result
    }

    private func uniquedEdges(_ edges: [MapEdge]) -> [MapEdge] {
        var seen: Set<String> = []
        return edges.filter { edge in
            let key = [edge.sourceId, edge.targetId].sorted().joined(separator: "::") + ":\(edge.kind)"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    // MARK: - Visibility helpers

    private func idsVisibleForTagFilter() -> Set<String> {
        guard let tagFilter else { return Set(nodes.map(\.id)) }
        let tagId = "tag:\(tagFilter)"
        let connected = idsConnected(to: [tagId])
        return connected.union([tagId])
    }

    private func idsConnected(to ids: Set<String>) -> Set<String> {
        Set(edges.flatMap { edge -> [String] in
            if ids.contains(edge.sourceId) { return [edge.targetId] }
            if ids.contains(edge.targetId) { return [edge.sourceId] }
            return []
        })
    }

    private func idsConnected(to ids: [String]) -> Set<String> {
        idsConnected(to: Set(ids))
    }

    private func springLengthMultiplier(for edge: MapEdge) -> Double {
        switch edge.kind {
        case .relation:
            return edge.isManual ? 0.72 : 0.82
        case .tag:
            return 0.88
        case .sharedTag:
            return 1.08
        }
    }

    // MARK: - Deterministic geometry

    private func angleFor(index: Int, total: Int, phase: Double) -> Double {
        let goldenAngle = Double.pi * (3 - sqrt(5))
        if total < 7 {
            return (Double(index) / Double(max(total, 1))) * 2 * .pi + phase
        }
        return Double(index) * goldenAngle + phase
    }

    private func jitterPoint(for key: String, radius: Double) -> CGPoint {
        let hash = stableHash(key)
        let angle = Double(hash % 628) / 100
        let distance = radius * (0.35 + Double((hash / 631) % 100) / 160)
        return CGPoint(x: cos(angle) * distance, y: sin(angle) * distance)
    }

    private func deterministicDepth(for key: String, magnitude: Double) -> Double {
        let hash = stableHash("z:\(key)")
        let normalized = Double(Int(hash % 1_000) - 500) / 500
        return normalized * magnitude
    }

    private func stableHash(_ value: String) -> UInt64 {
        value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { partial, byte in
            (partial ^ UInt64(byte)).multipliedReportingOverflow(by: 1_099_511_628_211).partialValue
        }
    }
}

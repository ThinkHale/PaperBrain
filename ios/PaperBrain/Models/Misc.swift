import Foundation

struct MindmapPosition: Codable, Identifiable {
    let id: UUID
    let userId: UUID
    let nodeId: String
    var x: Double
    var y: Double
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case nodeId = "node_id"
        case x, y
        case updatedAt = "updated_at"
    }
}

struct HandwritingCorrection: Codable {
    let userId: UUID
    let original: String
    let correction: String
    let contextSnippet: String?
    let noteId: UUID?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case original, correction
        case contextSnippet = "context_snippet"
        case noteId = "note_id"
    }
}

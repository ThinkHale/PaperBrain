import Foundation

struct Relation: Codable, Identifiable {
    let id: String
    let userId: String?
    let fromId: String
    let toId: String
    let score: Double?
    let reason: String?
    let manual: Bool?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case fromId = "from_id"
        case toId = "to_id"
        case score
        case reason
        case manual
        case createdAt = "created_at"
    }
}

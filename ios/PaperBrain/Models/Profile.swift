import Foundation

enum AIModel: String, Codable, CaseIterable {
    case sonnet4 = "claude-sonnet-4-20250514"
    case haiku4 = "claude-haiku-4-5-20251001"
    case opus4 = "claude-opus-4-20250514"

    var displayName: String {
        switch self {
        case .sonnet4: return "Claude Sonnet 4"
        case .haiku4: return "Claude Haiku 4.5"
        case .opus4: return "Claude Opus 4"
        }
    }
}

struct Profile: Codable, Identifiable {
    let id: String
    var displayName: String?
    var model: String?
    var handwritingContext: String?
    let createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case model
        case handwritingContext = "handwriting_context"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var aiModel: AIModel {
        guard let m = model else { return .sonnet4 }
        return AIModel(rawValue: m) ?? .sonnet4
    }
}

import Foundation

enum AIModel: String, Codable, CaseIterable {
    case gpt54Mini = "gpt-5.4-mini"
    case gpt54Nano = "gpt-5.4-nano"
    case gpt54 = "gpt-5.4"
    case gpt55 = "gpt-5.5"

    var displayName: String {
        switch self {
        case .gpt54Mini: return "GPT-5.4 mini"
        case .gpt54Nano: return "GPT-5.4 nano"
        case .gpt54: return "GPT-5.4"
        case .gpt55: return "GPT-5.5"
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
        guard let m = model else { return .gpt54Mini }
        return AIModel(rawValue: m) ?? .gpt54Mini
    }

    static let availableModels = AIModel.allCases.map(\.rawValue)

    var modelName: String {
        aiModel.rawValue
    }
}

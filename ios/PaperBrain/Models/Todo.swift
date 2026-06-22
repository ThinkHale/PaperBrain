import Foundation

enum TodoSource: String, Codable {
    case ai
    case manual
}

/// A to-do item, either extracted by the AI from a note or added by the user.
struct Todo: Codable, Identifiable, Equatable {
    let id: String
    var userId: String?
    var noteId: String?
    var text: String
    var done: Bool
    var dueDate: String?
    var source: TodoSource
    var position: Int
    let createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case noteId = "note_id"
        case text
        case done
        case dueDate = "due_date"
        case source
        case position
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct TodoCreate: Encodable {
    let userId: String
    var noteId: String?
    let text: String
    var dueDate: String?
    var source: String = TodoSource.manual.rawValue
    var position: Int = 0

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case noteId = "note_id"
        case text
        case dueDate = "due_date"
        case source
        case position
    }
}

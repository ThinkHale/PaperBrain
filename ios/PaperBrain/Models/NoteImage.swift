import Foundation

struct NoteImage: Codable, Identifiable, Hashable {
    let id: UUID
    let noteId: UUID
    let storagePath: String
    let pageNumber: Int
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case noteId = "note_id"
        case storagePath = "storage_path"
        case pageNumber = "page_number"
        case createdAt = "created_at"
    }
}

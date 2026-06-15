import Foundation

enum ProcessingState: String, Codable {
    case pending = "pending"
    case transcribing = "transcribing"
    case summarizing = "summarizing"
    case done = "done"
    case error = "error"
}

enum SourceType: String, Codable {
    case image = "image"
    case pdf = "pdf"
}

struct Note: Codable, Identifiable {
    let id: String
    var userId: String?
    var title: String?
    var transcription: String?
    var organized: String?
    var summary: String?
    var tags: [String]?
    var keyPoints: [String]?
    var sourceType: SourceType?
    var processingState: ProcessingState?
    var errorMessage: String?
    let createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case transcription
        case organized
        case summary
        case tags
        case keyPoints = "key_points"
        case sourceType = "source_type"
        case processingState = "processing_state"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayTitle: String {
        if let t = title, !t.isEmpty { return t }
        return "Untitled Note"
    }

    var isProcessing: Bool {
        guard let state = processingState else { return false }
        return state == .pending || state == .transcribing || state == .summarizing
    }

    var formattedDate: String {
        guard let createdAt = createdAt else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: createdAt) {
            let display = DateFormatter()
            display.dateStyle = .medium
            display.timeStyle = .short
            return display.string(from: date)
        }
        return createdAt
    }
}

struct NoteImage: Codable, Identifiable {
    let id: String
    let noteId: String
    let userId: String?
    let storagePath: String
    let pageNumber: Int?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case noteId = "note_id"
        case userId = "user_id"
        case storagePath = "storage_path"
        case pageNumber = "page_number"
        case createdAt = "created_at"
    }
}

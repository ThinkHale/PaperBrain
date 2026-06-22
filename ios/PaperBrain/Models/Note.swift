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
    case typed = "typed"
    case drawing = "drawing"
    case voice = "voice"
    case mixed = "mixed"
}

/// The physical/medium kind of a note. Detected by the AI for scans, set
/// explicitly for in-app capture.
enum NoteType: String, Codable, CaseIterable {
    case handwritten, postit, notebook, whiteboard, printed, diagram, mixed
    case typed, drawing, voice, pdf

    var displayName: String {
        switch self {
        case .handwritten: return "Handwritten"
        case .postit:      return "Post-it"
        case .notebook:    return "Notebook"
        case .whiteboard:  return "Whiteboard"
        case .printed:     return "Printed"
        case .diagram:     return "Diagram"
        case .mixed:       return "Mixed"
        case .typed:       return "Typed"
        case .drawing:     return "Drawing"
        case .voice:       return "Voice"
        case .pdf:         return "PDF"
        }
    }

    var iconName: String {
        switch self {
        case .handwritten: return "hand.draw"
        case .postit:      return "note"
        case .notebook:    return "book"
        case .whiteboard:  return "rectangle.on.rectangle"
        case .printed:     return "doc.text"
        case .diagram:     return "flowchart"
        case .mixed:       return "square.grid.2x2"
        case .typed:       return "keyboard"
        case .drawing:     return "pencil.and.scribble"
        case .voice:       return "waveform"
        case .pdf:         return "doc.richtext"
        }
    }
}

/// A word the AI couldn't read, with its location on the page so we can show
/// the user a cropped snippet for context.
struct UnclearRegion: Codable {
    let guess: String?
    let page: Int?
    let x: Double?
    let y: Double?
    let w: Double?
    let h: Double?
    let context: String?
}

struct Note: Codable, Identifiable {
    let id: String
    var userId: String?
    var title: String?
    var transcription: String?
    var organized: String?
    var summary: String?
    var tags: [String]?
    var categories: [String]?
    var keyPoints: [String]?
    var sourceType: SourceType?
    var noteType: String?
    var unclearRegions: [UnclearRegion]?
    var drawingPath: String?
    var audioPath: String?
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
        case categories
        case keyPoints = "key_points"
        case sourceType = "source_type"
        case noteType = "note_type"
        case unclearRegions = "unclear_regions"
        case drawingPath = "drawing_path"
        case audioPath = "audio_path"
        case processingState = "processing_state"
        case errorMessage = "error_message"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// Resolved note medium, falling back to the source type for legacy notes.
    var noteTypeValue: NoteType {
        if let nt = noteType, let value = NoteType(rawValue: nt) { return value }
        switch sourceType {
        case .pdf:     return .pdf
        case .typed:   return .typed
        case .drawing: return .drawing
        case .voice:   return .voice
        default:       return .handwritten
        }
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

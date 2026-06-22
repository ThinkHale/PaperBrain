import Foundation
import Supabase

/// Singleton Supabase client + all database CRUD operations.
@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: Config.supabaseURL)!,
            supabaseKey: Config.supabaseAnonKey
        )
    }

    // MARK: - Auth

    func signIn(email: String, password: String) async throws {
        try await client.auth.signIn(email: email, password: password)
    }

    func signUp(email: String, password: String) async throws {
        try await client.auth.signUp(email: email, password: password)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    // MARK: - Profile

    func fetchProfile(userId: UUID) async throws -> Profile {
        let profiles: [Profile] = try await client
            .from("profiles")
            .select()
            .eq("id", value: userId.uuidString)
            .execute()
            .value
        guard let profile = profiles.first else { throw AppError.notFound }
        return profile
    }

    func updateProfile(id: UUID, displayName: String?, model: String) async throws {
        struct Update: Encodable {
            let displayName: String?
            let model: String
            let updatedAt: String
            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case model
                case updatedAt = "updated_at"
            }
        }
        try await client
            .from("profiles")
            .update(Update(displayName: displayName, model: model, updatedAt: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Notes

    func fetchNotes(userId: UUID) async throws -> [Note] {
        try await client
            .from("notes")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchNote(id: String) async throws -> Note {
        let notes: [Note] = try await client
            .from("notes")
            .select()
            .eq("id", value: id)
            .limit(1)
            .execute()
            .value
        guard let note = notes.first else { throw AppError.notFound }
        return note
    }

    func updateNoteTitle(noteId: String, title: String) async throws {
        struct Update: Encodable {
            let title: String
            let updatedAt: String
            enum CodingKeys: String, CodingKey {
                case title
                case updatedAt = "updated_at"
            }
        }
        try await client
            .from("notes")
            .update(Update(title: title, updatedAt: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: noteId)
            .execute()
    }

    func updateNoteTags(noteId: String, tags: [String]) async throws {
        struct Update: Encodable {
            let tags: [String]
            let updatedAt: String
            enum CodingKeys: String, CodingKey {
                case tags
                case updatedAt = "updated_at"
            }
        }
        try await client
            .from("notes")
            .update(Update(tags: tags, updatedAt: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: noteId)
            .execute()
    }

    func updateNoteCategories(noteId: String, categories: [String]) async throws {
        struct Update: Encodable {
            let categories: [String]
            let updatedAt: String
            enum CodingKeys: String, CodingKey {
                case categories
                case updatedAt = "updated_at"
            }
        }
        try await client
            .from("notes")
            .update(Update(categories: categories, updatedAt: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: noteId)
            .execute()
    }

    func updateNoteAssetPath(noteId: String, drawingPath: String? = nil, audioPath: String? = nil) async throws {
        struct Update: Encodable {
            let drawingPath: String?
            let audioPath: String?
            enum CodingKeys: String, CodingKey {
                case drawingPath = "drawing_path"
                case audioPath = "audio_path"
            }
        }
        try await client
            .from("notes")
            .update(Update(drawingPath: drawingPath, audioPath: audioPath))
            .eq("id", value: noteId)
            .execute()
    }

    /// After an Apple Pencil note is processed as an image, mark it as a drawing
    /// and attach the raw PKDrawing blob so it stays re-editable.
    func setDrawingMeta(noteId: String, drawingPath: String) async throws {
        struct Update: Encodable {
            let noteType = NoteType.drawing.rawValue
            let sourceType = SourceType.drawing.rawValue
            let drawingPath: String
            enum CodingKeys: String, CodingKey {
                case noteType = "note_type"
                case sourceType = "source_type"
                case drawingPath = "drawing_path"
            }
        }
        try await client
            .from("notes")
            .update(Update(drawingPath: drawingPath))
            .eq("id", value: noteId)
            .execute()
    }

    func updateNoteOrganized(noteId: String, organized: String) async throws {
        struct Update: Encodable {
            let organized: String
            let updatedAt: String
            enum CodingKeys: String, CodingKey {
                case organized
                case updatedAt = "updated_at"
            }
        }
        try await client
            .from("notes")
            .update(Update(organized: organized, updatedAt: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: noteId)
            .execute()
    }

    func deleteNote(id: String) async throws {
        try await client
            .from("notes")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Note Images

    func fetchNoteImages(noteId: String) async throws -> [NoteImage] {
        try await client
            .from("note_images")
            .select()
            .eq("note_id", value: noteId)
            .order("page_number", ascending: true)
            .execute()
            .value
    }

    // MARK: - Annotations

    func fetchAnnotations(noteId: String) async throws -> [Annotation] {
        try await client
            .from("annotations")
            .select()
            .eq("note_id", value: noteId)
            .execute()
            .value
    }

    func insertAnnotation(_ annotation: Annotation) async throws {
        let session = try await client.auth.session
        struct Insert: Encodable {
            let noteId: String
            let userId: UUID
            let imageIndex: Int
            let shapeType: ShapeType
            let shapeData: ShapeData
            let tag: String?
            let label: String?
            let color: String?
            let regionContent: String?

            enum CodingKeys: String, CodingKey {
                case noteId = "note_id"
                case userId = "user_id"
                case imageIndex = "image_index"
                case shapeType = "shape_type"
                case shapeData = "shape_data"
                case tag
                case label
                case color
                case regionContent = "region_content"
            }
        }
        let row = Insert(
            noteId: annotation.noteId,
            userId: session.user.id,
            imageIndex: annotation.imageIndex,
            shapeType: annotation.shapeType,
            shapeData: annotation.shapeData,
            tag: annotation.tag,
            label: annotation.label,
            color: annotation.color,
            regionContent: annotation.regionContent
        )
        try await client
            .from("annotations")
            .insert(row)
            .execute()
    }

    func updateAnnotationContent(id: String, regionContent: String) async throws {
        struct Update: Encodable {
            let regionContent: String
            enum CodingKeys: String, CodingKey { case regionContent = "region_content" }
        }
        try await client
            .from("annotations")
            .update(Update(regionContent: regionContent))
            .eq("id", value: id)
            .execute()
    }

    func deleteAnnotation(id: String) async throws {
        try await client
            .from("annotations")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Relations

    func fetchRelations(noteId: String) async throws -> [Relation] {
        // Fetch where note is either end of the relation
        let asFrom: [Relation] = try await client
            .from("relations")
            .select()
            .eq("from_id", value: noteId)
            .execute()
            .value
        let asTo: [Relation] = try await client
            .from("relations")
            .select()
            .eq("to_id", value: noteId)
            .execute()
            .value
        return (asFrom + asTo).sorted { $0.score > $1.score }
    }

    func fetchAllRelations(userId: UUID) async throws -> [Relation] {
        // Relations are scoped by user via RLS; fetch all
        try await client
            .from("relations")
            .select()
            .execute()
            .value
    }

    func insertManualRelation(fromId: String, toId: String, userId: UUID) async throws {
        struct NewRelation: Encodable {
            let userId: UUID
            let fromId: String
            let toId: String
            let score: Double
            let manual: Bool
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case fromId = "from_id"
                case toId = "to_id"
                case score, manual
            }
        }
        try await client
            .from("relations")
            .insert(NewRelation(userId: userId, fromId: fromId, toId: toId, score: 1.0, manual: true))
            .execute()
    }

    func deleteRelation(id: String) async throws {
        try await client
            .from("relations")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Handwriting Corrections

    func insertCorrection(_ correction: HandwritingCorrection) async throws {
        try await client
            .from("handwriting_corrections")
            .insert(correction)
            .execute()
    }

    // MARK: - Mindmap Positions

    func fetchMindmapPositions(userId: UUID) async throws -> [MindmapPosition] {
        try await client
            .from("mindmap_positions")
            .select()
            .eq("user_id", value: userId.uuidString)
            .execute()
            .value
    }

    func upsertMindmapPosition(userId: UUID, nodeType: String, nodeId: String, x: Double, y: Double) async throws {
        struct Upsert: Encodable {
            let userId: UUID
            let nodeType: String
            let nodeId: String
            let x, y: Double
            let updatedAt: String
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case nodeType = "node_type"
                case nodeId = "node_id"
                case x, y
                case updatedAt = "updated_at"
            }
        }
        try await client
            .from("mindmap_positions")
            .upsert(Upsert(userId: userId, nodeType: nodeType, nodeId: nodeId, x: x, y: y, updatedAt: ISO8601DateFormatter().string(from: Date())),
                    onConflict: "user_id,node_type,node_id")
            .execute()
    }

    // MARK: - Tags (vocabulary)

    func fetchTags(userId: UUID) async throws -> [Tag] {
        try await client
            .from("tags")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("kind", ascending: true)
            .order("name", ascending: true)
            .execute()
            .value
    }

    @discardableResult
    func insertTag(userId: UUID, name: String, kind: TagKind, color: String?) async throws -> Tag {
        let row = TagCreate(userId: userId.uuidString, name: name, kind: kind.rawValue, color: color)
        return try await client
            .from("tags")
            .insert(row)
            .select()
            .single()
            .execute()
            .value
    }

    func renameTag(id: String, name: String) async throws {
        struct Update: Encodable { let name: String }
        try await client.from("tags").update(Update(name: name)).eq("id", value: id).execute()
    }

    func updateTagColor(id: String, color: String) async throws {
        struct Update: Encodable { let color: String }
        try await client.from("tags").update(Update(color: color)).eq("id", value: id).execute()
    }

    func deleteTag(id: String) async throws {
        try await client.from("tags").delete().eq("id", value: id).execute()
    }

    // MARK: - Todos

    func fetchTodos(userId: UUID) async throws -> [Todo] {
        try await client
            .from("todos")
            .select()
            .eq("user_id", value: userId.uuidString)
            .order("done", ascending: true)
            .order("position", ascending: true)
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchTodos(noteId: String) async throws -> [Todo] {
        try await client
            .from("todos")
            .select()
            .eq("note_id", value: noteId)
            .order("position", ascending: true)
            .execute()
            .value
    }

    @discardableResult
    func insertTodo(_ todo: TodoCreate) async throws -> Todo {
        try await client
            .from("todos")
            .insert(todo)
            .select()
            .single()
            .execute()
            .value
    }

    func setTodoDone(id: String, done: Bool) async throws {
        struct Update: Encodable {
            let done: Bool
            let updatedAt: String
            enum CodingKeys: String, CodingKey {
                case done
                case updatedAt = "updated_at"
            }
        }
        try await client
            .from("todos")
            .update(Update(done: done, updatedAt: ISO8601DateFormatter().string(from: Date())))
            .eq("id", value: id)
            .execute()
    }

    func updateTodoText(id: String, text: String) async throws {
        struct Update: Encodable { let text: String }
        try await client.from("todos").update(Update(text: text)).eq("id", value: id).execute()
    }

    func deleteTodo(id: String) async throws {
        try await client.from("todos").delete().eq("id", value: id).execute()
    }
}

// MARK: - Shared errors

enum AppError: Error, LocalizedError {
    case notFound
    case unauthorized
    case processingFailed(String)
    case invalidData

    var errorDescription: String? {
        switch self {
        case .notFound: return "Record not found"
        case .unauthorized: return "Please sign in again"
        case .processingFailed(let msg): return msg
        case .invalidData: return "Unexpected data format"
        }
    }
}

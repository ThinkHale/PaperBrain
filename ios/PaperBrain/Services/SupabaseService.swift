import Foundation
import Supabase

/// Singleton Supabase client + all database CRUD operations.
@MainActor
final class SupabaseService {
    static let shared = SupabaseService()

    let client: SupabaseClient

    private init() {
        client = SupabaseClient(
            supabaseURL: AppConfig.supabaseURL,
            supabaseKey: AppConfig.supabaseAnonKey
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

    func updateProfile(id: UUID, displayName: String?, claudeModel: String) async throws {
        struct Update: Encodable {
            let displayName: String?
            let claudeModel: String
            let updatedAt: String
            enum CodingKeys: String, CodingKey {
                case displayName = "display_name"
                case claudeModel = "claude_model"
                case updatedAt = "updated_at"
            }
        }
        try await client
            .from("profiles")
            .update(Update(displayName: displayName, claudeModel: claudeModel, updatedAt: ISO8601DateFormatter().string(from: Date())))
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

    func fetchNote(id: UUID) async throws -> Note {
        let notes: [Note] = try await client
            .from("notes")
            .select()
            .eq("id", value: id.uuidString)
            .limit(1)
            .execute()
            .value
        guard let note = notes.first else { throw AppError.notFound }
        return note
    }

    func updateNoteTitle(noteId: UUID, title: String) async throws {
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
            .eq("id", value: noteId.uuidString)
            .execute()
    }

    func updateNoteTags(noteId: UUID, tags: [String]) async throws {
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
            .eq("id", value: noteId.uuidString)
            .execute()
    }

    func updateNoteOrganized(noteId: UUID, organized: String) async throws {
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
            .eq("id", value: noteId.uuidString)
            .execute()
    }

    func deleteNote(id: UUID) async throws {
        try await client
            .from("notes")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Note Images

    func fetchNoteImages(noteId: UUID) async throws -> [NoteImage] {
        try await client
            .from("note_images")
            .select()
            .eq("note_id", value: noteId.uuidString)
            .order("page_number", ascending: true)
            .execute()
            .value
    }

    // MARK: - Annotations

    func fetchAnnotations(noteId: UUID) async throws -> [Annotation] {
        try await client
            .from("annotations")
            .select()
            .eq("note_id", value: noteId.uuidString)
            .execute()
            .value
    }

    func insertAnnotation(_ annotation: Annotation) async throws {
        try await client
            .from("annotations")
            .insert(annotation)
            .execute()
    }

    func updateAnnotationContent(id: UUID, regionContent: String) async throws {
        struct Update: Encodable {
            let regionContent: String
            enum CodingKeys: String, CodingKey { case regionContent = "region_content" }
        }
        try await client
            .from("annotations")
            .update(Update(regionContent: regionContent))
            .eq("id", value: id.uuidString)
            .execute()
    }

    func deleteAnnotation(id: UUID) async throws {
        try await client
            .from("annotations")
            .delete()
            .eq("id", value: id.uuidString)
            .execute()
    }

    // MARK: - Relations

    func fetchRelations(noteId: UUID) async throws -> [Relation] {
        // Fetch where note is either end of the relation
        let asFrom: [Relation] = try await client
            .from("relations")
            .select()
            .eq("from_id", value: noteId.uuidString)
            .execute()
            .value
        let asTo: [Relation] = try await client
            .from("relations")
            .select()
            .eq("to_id", value: noteId.uuidString)
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

    func insertManualRelation(fromId: UUID, toId: UUID) async throws {
        struct NewRelation: Encodable {
            let fromId: UUID
            let toId: UUID
            let score: Double
            let manual: Bool
            enum CodingKeys: String, CodingKey {
                case fromId = "from_id"
                case toId = "to_id"
                case score, manual
            }
        }
        try await client
            .from("relations")
            .insert(NewRelation(fromId: fromId, toId: toId, score: 1.0, manual: true))
            .execute()
    }

    func deleteRelation(id: UUID) async throws {
        try await client
            .from("relations")
            .delete()
            .eq("id", value: id.uuidString)
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

    func upsertMindmapPosition(userId: UUID, nodeId: String, x: Double, y: Double) async throws {
        struct Upsert: Encodable {
            let userId: UUID
            let nodeId: String
            let x, y: Double
            let updatedAt: String
            enum CodingKeys: String, CodingKey {
                case userId = "user_id"
                case nodeId = "node_id"
                case x, y
                case updatedAt = "updated_at"
            }
        }
        try await client
            .from("mindmap_positions")
            .upsert(Upsert(userId: userId, nodeId: nodeId, x: x, y: y, updatedAt: ISO8601DateFormatter().string(from: Date())),
                    onConflict: "user_id,node_id")
            .execute()
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

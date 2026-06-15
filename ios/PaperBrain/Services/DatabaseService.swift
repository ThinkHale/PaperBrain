import Foundation

struct MindmapPosition: Codable, Identifiable {
    let id: String
    let userId: String?
    let nodeType: String
    let nodeId: String
    var x: Double
    var y: Double
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case nodeType = "node_type"
        case nodeId = "node_id"
        case x, y
        case updatedAt = "updated_at"
    }
}

final class DatabaseService {
    static let shared = DatabaseService()
    private let client = SupabaseClient.shared
    private init() {}

    private let base = "/rest/v1"

    // MARK: - Notes

    func getAllNotes() async throws -> [Note] {
        return try await client.request(
            method: "GET",
            path: "\(base)/notes",
            queryItems: [URLQueryItem(name: "order", value: "created_at.desc")]
        )
    }

    func getNote(id: String) async throws -> Note {
        return try await client.request(
            method: "GET",
            path: "\(base)/notes",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id)")],
            extraHeaders: ["Accept": "application/vnd.pgrst.object+json"]
        )
    }

    func saveNote(id: String, fields: [String: Any]) async throws -> Note {
        let bodyData = try JSONSerialization.data(withJSONObject: fields)
        let data = try await client.requestData(
            method: "PATCH",
            path: "\(base)/notes",
            body: bodyData,
            contentType: "application/json",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id)")]
        )

        // PATCH may return array; handle both
        let decoder = makeDecoder()
        if let note = try? decoder.decode(Note.self, from: data) {
            return note
        }
        let notes = try decoder.decode([Note].self, from: data)
        guard let first = notes.first else { throw SupabaseError.noData }
        return first
    }

    func createNote(fields: [String: Any]) async throws -> Note {
        let bodyData = try JSONSerialization.data(withJSONObject: fields)
        let data = try await client.requestData(
            method: "POST",
            path: "\(base)/notes",
            body: bodyData,
            contentType: "application/json",
            queryItems: nil
        )
        let decoder = makeDecoder()
        if let note = try? decoder.decode(Note.self, from: data) {
            return note
        }
        let notes = try decoder.decode([Note].self, from: data)
        guard let first = notes.first else { throw SupabaseError.noData }
        return first
    }

    func deleteNote(id: String) async throws {
        _ = try await client.requestData(
            method: "DELETE",
            path: "\(base)/notes",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id)")]
        )
    }

    // MARK: - Note Images

    func getNoteImages(noteId: String) async throws -> [NoteImage] {
        return try await client.request(
            method: "GET",
            path: "\(base)/note_images",
            queryItems: [
                URLQueryItem(name: "note_id", value: "eq.\(noteId)"),
                URLQueryItem(name: "order", value: "page_number.asc")
            ]
        )
    }

    func addNoteImage(_ image: NoteImage) async throws -> NoteImage {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData = try encoder.encode(image)
        let data = try await client.requestData(
            method: "POST",
            path: "\(base)/note_images",
            body: bodyData,
            contentType: "application/json",
            queryItems: nil
        )
        let decoder = makeDecoder()
        if let img = try? decoder.decode(NoteImage.self, from: data) { return img }
        let imgs = try decoder.decode([NoteImage].self, from: data)
        guard let first = imgs.first else { throw SupabaseError.noData }
        return first
    }

    // MARK: - Annotations

    func getAnnotations(noteId: String) async throws -> [Annotation] {
        return try await client.request(
            method: "GET",
            path: "\(base)/annotations",
            queryItems: [URLQueryItem(name: "note_id", value: "eq.\(noteId)")]
        )
    }

    func saveAnnotation(_ annotation: AnnotationCreate) async throws -> Annotation {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let bodyData = try encoder.encode(annotation)
        let data = try await client.requestData(
            method: "POST",
            path: "\(base)/annotations",
            body: bodyData,
            contentType: "application/json",
            queryItems: nil
        )
        let decoder = makeDecoder()
        if let a = try? decoder.decode(Annotation.self, from: data) { return a }
        let arr = try decoder.decode([Annotation].self, from: data)
        guard let first = arr.first else { throw SupabaseError.noData }
        return first
    }

    func updateAnnotation(id: String, fields: [String: Any]) async throws -> Annotation {
        let bodyData = try JSONSerialization.data(withJSONObject: fields)
        let data = try await client.requestData(
            method: "PATCH",
            path: "\(base)/annotations",
            body: bodyData,
            contentType: "application/json",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id)")]
        )
        let decoder = makeDecoder()
        if let a = try? decoder.decode(Annotation.self, from: data) { return a }
        let arr = try decoder.decode([Annotation].self, from: data)
        guard let first = arr.first else { throw SupabaseError.noData }
        return first
    }

    func deleteAnnotation(id: String) async throws {
        _ = try await client.requestData(
            method: "DELETE",
            path: "\(base)/annotations",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(id)")]
        )
    }

    // MARK: - Relations

    func getRelations(noteId: String) async throws -> [Relation] {
        return try await client.request(
            method: "GET",
            path: "\(base)/relations",
            queryItems: [URLQueryItem(name: "or", value: "(from_id.eq.\(noteId),to_id.eq.\(noteId))")]
        )
    }

    func getAllRelations() async throws -> [Relation] {
        return try await client.request(
            method: "GET",
            path: "\(base)/relations",
            queryItems: [URLQueryItem(name: "order", value: "score.desc")]
        )
    }

    // MARK: - Mindmap Positions

    func getMindmapPositions() async throws -> [MindmapPosition] {
        return try await client.request(
            method: "GET",
            path: "\(base)/mindmap_positions"
        )
    }

    func saveMindmapPosition(nodeType: String, nodeId: String, x: Double, y: Double) async throws {
        guard let userId = client.currentUserId else { throw SupabaseError.notAuthenticated }
        let body: [String: Any] = [
            "user_id": userId,
            "node_type": nodeType,
            "node_id": nodeId,
            "x": x,
            "y": y,
            "updated_at": ISO8601DateFormatter().string(from: Date())
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        _ = try await client.requestData(
            method: "POST",
            path: "\(base)/mindmap_positions",
            body: bodyData,
            contentType: "application/json",
            queryItems: nil
        )
    }

    // MARK: - Profile

    func getProfile() async throws -> Profile {
        guard let userId = client.currentUserId else { throw SupabaseError.notAuthenticated }
        let data = try await client.requestData(
            method: "GET",
            path: "\(base)/profiles",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(userId)")]
        )
        let decoder = makeDecoder()
        let profiles = try decoder.decode([Profile].self, from: data)
        if let p = profiles.first { return p }
        // create profile if missing
        let newBody: [String: Any] = ["id": userId]
        let newData = try JSONSerialization.data(withJSONObject: newBody)
        let created = try await client.requestData(
            method: "POST",
            path: "\(base)/profiles",
            body: newData,
            contentType: "application/json",
            queryItems: nil
        )
        if let p = try? decoder.decode(Profile.self, from: created) { return p }
        let arr = try decoder.decode([Profile].self, from: created)
        guard let first = arr.first else { throw SupabaseError.noData }
        return first
    }

    func updateProfile(displayName: String?, model: String?) async throws {
        guard let userId = client.currentUserId else { throw SupabaseError.notAuthenticated }
        var fields: [String: Any] = ["updated_at": ISO8601DateFormatter().string(from: Date())]
        if let dn = displayName { fields["display_name"] = dn }
        if let m = model { fields["model"] = m }
        let bodyData = try JSONSerialization.data(withJSONObject: fields)
        _ = try await client.requestData(
            method: "PATCH",
            path: "\(base)/profiles",
            body: bodyData,
            contentType: "application/json",
            queryItems: [URLQueryItem(name: "id", value: "eq.\(userId)")]
        )
    }

    // MARK: - Helper

    private func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }
}

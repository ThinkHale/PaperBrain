import Foundation
import Supabase

// MARK: - Payload / Response types

private struct ProcessNotePayload: Encodable {
    let images: [String]              // base64 data-URLs
    let mode: String                  // "full" | "region"
    let tag: String?
    let noteId: String?

    enum CodingKeys: String, CodingKey {
        case images, mode, tag
        case noteId
    }
}

struct ProcessNoteResponse: Decodable {
    let ok: Bool
    let note: Note?
    let region: RegionResult?

    struct RegionResult: Decodable {
        let transcription: String?
        let content: String?
        let tag: String?
    }
}

private struct FindRelationsPayload: Encodable {
    let noteId: String
}

private struct LearnHandwritingPayload: Encodable {
    // Edge function accepts an empty body as a synthesis trigger.
    let userId: String
    enum CodingKeys: String, CodingKey { case userId = "user_id" }
}

// MARK: - Service

/// Invokes Supabase Edge Functions.
@MainActor
final class EdgeFunctionService {
    static let shared = EdgeFunctionService()
    private var client: SupabaseClient { SupabaseService.shared.client }

    private init() {}

    /// Send one or more images to `process-note` and return the created Note.
    func processNote(images: [String]) async throws -> Note {
        let payload = ProcessNotePayload(images: images, mode: "full", tag: nil, noteId: nil)
        let response: ProcessNoteResponse = try await client.functions
            .invoke("process-note", options: FunctionInvokeOptions(body: payload))
        guard let note = response.note else {
            throw AppError.processingFailed("Edge function did not return a note")
        }
        return note
    }

    /// Re-process a cropped annotation region.
    func processRegion(image: String, tag: String?, noteId: String) async throws -> ProcessNoteResponse.RegionResult {
        let payload = ProcessNotePayload(images: [image], mode: "region", tag: tag, noteId: noteId)
        let response: ProcessNoteResponse = try await client.functions
            .invoke("process-note", options: FunctionInvokeOptions(body: payload))
        guard let region = response.region else {
            throw AppError.processingFailed("No region result returned")
        }
        return region
    }

    /// Fire-and-forget: find related notes for a newly created note.
    func findRelations(noteId: String) {
        Task {
            let payload = FindRelationsPayload(noteId: noteId)
            _ = try? await client.functions
                .invoke("find-relations", options: FunctionInvokeOptions(body: payload))
        }
    }

    /// Trigger the handwriting-learning edge function after saving corrections.
    func learnHandwriting(userId: UUID) {
        Task {
            let payload = LearnHandwritingPayload(userId: userId.uuidString)
            _ = try? await client.functions
                .invoke("learn-handwriting", options: FunctionInvokeOptions(body: payload))
        }
    }
}

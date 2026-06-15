import Foundation

final class StorageService {
    static let shared = StorageService()
    private let client = SupabaseClient.shared
    private init() {}

    func uploadImage(data: Data, path: String, contentType: String) async throws {
        _ = try await client.requestData(
            method: "POST",
            path: "/storage/v1/object/note-images/\(path)",
            body: data,
            contentType: contentType,
            queryItems: nil
        )
    }

    func publicURL(path: String) -> String {
        return "\(Config.supabaseURL)/storage/v1/object/public/note-images/\(path)"
    }

    func authenticatedURL(path: String) -> String {
        let token = client.accessToken ?? ""
        return "\(Config.supabaseURL)/storage/v1/object/authenticated/note-images/\(path)?token=\(token)"
    }

    func deleteImage(path: String) async throws {
        _ = try await client.requestData(
            method: "DELETE",
            path: "/storage/v1/object/note-images/\(path)",
            queryItems: nil
        )
    }
}

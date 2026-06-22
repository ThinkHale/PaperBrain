import Foundation
import UIKit
import Supabase

final class StorageService {
    static let shared = StorageService()
    private init() {}

    func signedURL(for path: String, bucket: String = "note-images", expiresIn: Int = 3600) async throws -> URL {
        let session = try await SupabaseService.shared.client.auth.session
        let encodedPath = path.split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: "\(Config.supabaseURL)/storage/v1/object/sign/\(bucket)/\(encodedPath)") else {
            throw AppError.invalidData
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["expiresIn": expiresIn])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
            throw AppError.processingFailed(String(data: data, encoding: .utf8) ?? "Failed to create signed URL")
        }

        let decoded = try JSONDecoder().decode(SignedURLResponse.self, from: data)
        let signedPath = decoded.signedURL.hasPrefix("/")
            ? "\(Config.supabaseURL)\(decoded.signedURL)"
            : decoded.signedURL
        guard let signedURL = URL(string: signedPath) else { throw AppError.invalidData }
        return signedURL
    }

    static func resize(_ image: UIImage, maxDimension: CGFloat = 1568) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxDimension else { return image }
        let scale = maxDimension / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    static func toDataURL(_ image: UIImage, compressionQuality: CGFloat = 0.88) -> String? {
        guard let data = image.jpegData(compressionQuality: compressionQuality) else { return nil }
        return "data:image/jpeg;base64,\(data.base64EncodedString())"
    }

    static func crop(_ image: UIImage, normalizedRect: CGRect) -> Data? {
        cropImage(image, normalizedRect: normalizedRect)?.jpegData(compressionQuality: 0.88)
    }

    /// Crop a UIImage to a normalized (0-1) rect, respecting orientation.
    static func cropImage(_ image: UIImage, normalizedRect: CGRect) -> UIImage? {
        let normalized = image.fixedOrientation()
        guard let cgImage = normalized.cgImage else { return nil }
        let clamped = normalizedRect.intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
        guard !clamped.isNull, clamped.width > 0, clamped.height > 0 else { return nil }
        let pixelRect = CGRect(
            x: clamped.minX * CGFloat(cgImage.width),
            y: clamped.minY * CGFloat(cgImage.height),
            width: clamped.width * CGFloat(cgImage.width),
            height: clamped.height * CGFloat(cgImage.height)
        ).integral
        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped)
    }

    /// Upload an arbitrary asset (audio / drawing blob) to the private note-assets bucket.
    func uploadAsset(data: Data, contentType: String, path: String) async throws {
        try await SupabaseService.shared.client.storage
            .from("note-assets")
            .upload(path, data: data, options: FileOptions(contentType: contentType, upsert: true))
    }

    func downloadAsset(path: String) async throws -> Data {
        try await SupabaseService.shared.client.storage
            .from("note-assets")
            .download(path: path)
    }
}

private extension UIImage {
    /// Redraw the image so its pixel buffer matches its displayed orientation,
    /// so normalized crop rects line up with what the user sees.
    func fixedOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: size)) }
    }
}

private struct SignedURLResponse: Decodable {
    let signedURL: String
}

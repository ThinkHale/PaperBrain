import Foundation
import UIKit

final class StorageService {
    static let shared = StorageService()
    private init() {}

    func signedURL(for path: String, expiresIn: Int = 3600) async throws -> URL {
        let session = try await SupabaseService.shared.client.auth.session
        let encodedPath = path.split(separator: "/")
            .map { String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: "\(Config.supabaseURL)/storage/v1/object/sign/note-images/\(encodedPath)") else {
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
        guard let cgImage = image.cgImage else { return nil }
        let pixelRect = CGRect(
            x: normalizedRect.minX * CGFloat(cgImage.width),
            y: normalizedRect.minY * CGFloat(cgImage.height),
            width: normalizedRect.width * CGFloat(cgImage.width),
            height: normalizedRect.height * CGFloat(cgImage.height)
        ).integral
        guard let cropped = cgImage.cropping(to: pixelRect) else { return nil }
        return UIImage(cgImage: cropped).jpegData(compressionQuality: 0.88)
    }
}

private struct SignedURLResponse: Decodable {
    let signedURL: String
}

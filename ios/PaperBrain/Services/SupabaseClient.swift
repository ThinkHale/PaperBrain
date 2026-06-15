import Foundation

struct SupabaseSession: Codable {
    var accessToken: String
    var refreshToken: String
    var userId: String
    var expiresAt: Date
}

enum SupabaseError: Error, LocalizedError {
    case notAuthenticated
    case invalidURL
    case httpError(Int, String)
    case decodingError(String)
    case noData

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated."
        case .invalidURL: return "Invalid URL."
        case .httpError(let code, let msg): return "HTTP \(code): \(msg)"
        case .decodingError(let msg): return "Decoding error: \(msg)"
        case .noData: return "No data received."
        }
    }
}

final class SupabaseClient {
    static let shared = SupabaseClient()

    private let sessionKey = "pb_session"
    private(set) var session: SupabaseSession?

    private let jsonDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let date = iso.date(from: str) { return date }
            let iso2 = ISO8601DateFormatter()
            iso2.formatOptions = [.withInternetDateTime]
            if let date = iso2.date(from: str) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date: \(str)")
        }
        return d
    }()

    private let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        return e
    }()

    private init() {
        loadSession()
    }

    var isAuthenticated: Bool { session != nil }
    var accessToken: String? { session?.accessToken }
    var currentUserId: String? { session?.userId }

    func authHeaders() -> [String: String] {
        var headers: [String: String] = [
            "apikey": Config.supabaseAnonKey,
            "Content-Type": "application/json"
        ]
        if let token = session?.accessToken {
            headers["Authorization"] = "Bearer \(token)"
        }
        return headers
    }

    func saveSession(_ session: SupabaseSession) {
        self.session = session
        if let data = try? JSONEncoder().encode(session) {
            UserDefaults.standard.set(data, forKey: sessionKey)
        }
    }

    func clearSession() {
        self.session = nil
        UserDefaults.standard.removeObject(forKey: sessionKey)
    }

    private func loadSession() {
        guard let data = UserDefaults.standard.data(forKey: sessionKey),
              let s = try? JSONDecoder().decode(SupabaseSession.self, from: data) else { return }
        self.session = s
    }

    // MARK: - Generic Request

    func request<T: Decodable>(
        method: String,
        path: String,
        body: Encodable? = nil,
        queryItems: [URLQueryItem]? = nil,
        extraHeaders: [String: String] = [:]
    ) async throws -> T {
        let data = try await rawRequest(method: method, path: path, body: body, queryItems: queryItems, extraHeaders: extraHeaders, retryOn401: true)
        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            throw SupabaseError.decodingError("\(error)")
        }
    }

    func requestData(
        method: String,
        path: String,
        body: Data? = nil,
        contentType: String = "application/json",
        queryItems: [URLQueryItem]? = nil
    ) async throws -> Data {
        return try await rawRequestData(method: method, path: path, body: body, contentType: contentType, queryItems: queryItems, retryOn401: true)
    }

    // MARK: - Private Helpers

    private func rawRequest(
        method: String,
        path: String,
        body: Encodable?,
        queryItems: [URLQueryItem]?,
        extraHeaders: [String: String],
        retryOn401: Bool
    ) async throws -> Data {
        var bodyData: Data? = nil
        if let body = body {
            bodyData = try JSONEncoder().encode(AnyEncodable(body))
        }
        return try await rawRequestData(method: method, path: path, body: bodyData, contentType: "application/json", queryItems: queryItems, retryOn401: retryOn401, extraHeaders: extraHeaders)
    }

    private func rawRequestData(
        method: String,
        path: String,
        body: Data?,
        contentType: String,
        queryItems: [URLQueryItem]?,
        retryOn401: Bool,
        extraHeaders: [String: String] = [:]
    ) async throws -> Data {
        guard var components = URLComponents(string: Config.supabaseURL + path) else {
            throw SupabaseError.invalidURL
        }
        if let qi = queryItems, !qi.isEmpty {
            components.queryItems = qi
        }
        guard let url = components.url else { throw SupabaseError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body

        var headers = authHeaders()
        headers["Content-Type"] = contentType
        for (k, v) in extraHeaders { headers[k] = v }
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw SupabaseError.noData
        }

        if httpResponse.statusCode == 401 && retryOn401 {
            try await refreshSession()
            return try await rawRequestData(method: method, path: path, body: body, contentType: contentType, queryItems: queryItems, retryOn401: false, extraHeaders: extraHeaders)
        }

        if httpResponse.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw SupabaseError.httpError(httpResponse.statusCode, msg)
        }

        return data
    }

    private func refreshSession() async throws {
        guard let refresh = session?.refreshToken else {
            throw SupabaseError.notAuthenticated
        }
        let body: [String: String] = ["refresh_token": refresh]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        let path = "/auth/v1/token"
        let qi = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        let data = try await rawRequestData(method: "POST", path: path, body: bodyData, contentType: "application/json", queryItems: qi, retryOn401: false)
        let resp = try JSONDecoder().decode(GoTrueResponse.self, from: data)
        let newSession = SupabaseSession(
            accessToken: resp.accessToken,
            refreshToken: resp.refreshToken,
            userId: resp.user.id,
            expiresAt: Date().addingTimeInterval(Double(resp.expiresIn ?? 3600))
        )
        saveSession(newSession)
    }
}

// MARK: - Helper types

struct GoTrueResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int?
    let user: GoTrueUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case user
    }
}

struct GoTrueUser: Decodable {
    let id: String
    let email: String?
}

struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void

    init<T: Encodable>(_ value: T) {
        _encode = value.encode
    }

    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

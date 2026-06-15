import Foundation

final class AuthService {
    static let shared = AuthService()
    private let client = SupabaseClient.shared
    private init() {}

    func signIn(email: String, password: String) async throws {
        let body: [String: String] = ["email": email, "password": password]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        guard var components = URLComponents(string: Config.supabaseURL + "/auth/v1/token") else {
            throw SupabaseError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "grant_type", value: "password")]
        guard let url = components.url else { throw SupabaseError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Auth failed"
            throw SupabaseError.httpError(http.statusCode, msg)
        }
        let resp = try JSONDecoder().decode(GoTrueResponse.self, from: data)
        let session = SupabaseSession(
            accessToken: resp.accessToken,
            refreshToken: resp.refreshToken,
            userId: resp.user.id,
            expiresAt: Date().addingTimeInterval(Double(resp.expiresIn ?? 3600))
        )
        client.saveSession(session)
    }

    func signUp(email: String, password: String) async throws {
        let body: [String: String] = ["email": email, "password": password]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        guard let url = URL(string: Config.supabaseURL + "/auth/v1/signup") else {
            throw SupabaseError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Sign up failed"
            throw SupabaseError.httpError(http.statusCode, msg)
        }
        let resp = try JSONDecoder().decode(GoTrueResponse.self, from: data)
        let session = SupabaseSession(
            accessToken: resp.accessToken,
            refreshToken: resp.refreshToken,
            userId: resp.user.id,
            expiresAt: Date().addingTimeInterval(Double(resp.expiresIn ?? 3600))
        )
        client.saveSession(session)
    }

    func signOut() async throws {
        defer { client.clearSession() }
        var headers = client.authHeaders()
        headers["Content-Type"] = "application/json"
        guard let url = URL(string: Config.supabaseURL + "/auth/v1/logout") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        _ = try? await URLSession.shared.data(for: request)
    }

    func refreshSession() async throws {
        guard let refresh = client.session?.refreshToken else {
            throw SupabaseError.notAuthenticated
        }
        let body: [String: String] = ["refresh_token": refresh]
        let bodyData = try JSONSerialization.data(withJSONObject: body)
        guard var components = URLComponents(string: Config.supabaseURL + "/auth/v1/token") else {
            throw SupabaseError.invalidURL
        }
        components.queryItems = [URLQueryItem(name: "grant_type", value: "refresh_token")]
        guard let url = components.url else { throw SupabaseError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
            let msg = String(data: data, encoding: .utf8) ?? "Refresh failed"
            throw SupabaseError.httpError(http.statusCode, msg)
        }
        let resp = try JSONDecoder().decode(GoTrueResponse.self, from: data)
        let session = SupabaseSession(
            accessToken: resp.accessToken,
            refreshToken: resp.refreshToken,
            userId: resp.user.id,
            expiresAt: Date().addingTimeInterval(Double(resp.expiresIn ?? 3600))
        )
        client.saveSession(session)
    }

    func restoreSession() async -> Bool {
        guard let session = client.session else { return false }
        if session.expiresAt > Date().addingTimeInterval(60) {
            return true
        }
        do {
            try await refreshSession()
            return true
        } catch {
            client.clearSession()
            return false
        }
    }
}

import Foundation
import Supabase

@MainActor
final class AuthViewModel: ObservableObject {
    @Published var isSignedIn = false
    @Published var currentUser: User?
    @Published var isLoading = true
    @Published var error: String?

    private let supabase = SupabaseService.shared

    func initialize() async {
        // Restore existing session then listen for changes
        if let session = try? await supabase.client.auth.session {
            currentUser = session.user
            isSignedIn = true
        }
        isLoading = false

        for await (_, session) in supabase.client.auth.authStateChanges {
            withAnimation {
                currentUser = session?.user
                isSignedIn = session != nil
            }
        }
    }

    func signIn(email: String, password: String) async {
        error = nil
        do {
            try await supabase.signIn(email: email, password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signUp(email: String, password: String) async {
        error = nil
        do {
            try await supabase.signUp(email: email, password: password)
        } catch {
            self.error = error.localizedDescription
        }
    }

    func signOut() async {
        try? await supabase.signOut()
    }
}

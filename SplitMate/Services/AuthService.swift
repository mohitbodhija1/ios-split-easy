internal import Auth
import Foundation
import Supabase

struct AuthService {
    let client: SupabaseClient

    func signUp(email: String, password: String, username: String) async throws {
        _ = try await client.auth.signUp(
            email: email,
            password: password,
            data: ["username": .string(username)]
        )
    }

    func signIn(email: String, password: String) async throws {
        _ = try await client.auth.signIn(email: email, password: password)
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func currentSession() async -> Session? {
        try? await client.auth.session
    }
}

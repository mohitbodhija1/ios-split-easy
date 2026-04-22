internal import Auth
import Foundation
import Observation
import Supabase

@Observable
@MainActor
final class SessionStore {
    private(set) var session: Session?
    private(set) var isBootstrapping = true
    private(set) var authError: String?

    let client = SupabaseProvider.shared
    private var authListenerTask: Task<Void, Never>?

    init() {
        if let configError = SupabaseCredentials.validationError {
            authError = configError
            isBootstrapping = false
            return
        }
        authListenerTask = Task { await self.listenAuth() }
    }

    private func listenAuth() async {
        for await change in client.auth.authStateChanges {
            let session = change.session
            await MainActor.run {
                self.session = session
                self.isBootstrapping = false
            }
            if session != nil {
                await PushCoordinator.shared.onSignedIn()
            }
        }
    }

    func clearAuthError() {
        authError = nil
    }

    func signIn(email: String, password: String) async {
        authError = nil
        do {
            try await AuthService(client: client).signIn(email: email, password: password)
        } catch {
            authError = error.localizedDescription
        }
    }

    func signUp(email: String, password: String, username: String) async {
        authError = nil
        do {
            try await AuthService(client: client).signUp(email: email, password: password, username: username)
        } catch {
            authError = error.localizedDescription
        }
    }

    func signOut() async {
        authError = nil
        do {
            try await AuthService(client: client).signOut()
        } catch {
            authError = error.localizedDescription
        }
    }
}

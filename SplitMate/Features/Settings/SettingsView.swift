internal import Auth
import SwiftUI

struct SettingsView: View {
    @Environment(SessionStore.self) private var sessionStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Account") {
                    if let email = sessionStore.session?.user.email {
                        LabeledContent("Email", value: email)
                    } else {
                        Text("Signed in")
                    }
                }
                Section {
                    Button("Sign out", role: .destructive) {
                        Task { await sessionStore.signOut() }
                    }
                }
            }
            .navigationTitle("Settings")
        }
    }
}

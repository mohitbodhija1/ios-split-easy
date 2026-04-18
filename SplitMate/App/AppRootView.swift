import SwiftUI
internal import Auth

struct AppRootView: View {
    @Environment(SessionStore.self) private var sessionStore
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var openAuthWithSignUp = false

    var body: some View {
        Group {
            if sessionStore.isBootstrapping {
                ProgressView("Loading…")
            } else if sessionStore.session != nil {
                MainTabView()
            } else if !hasCompletedOnboarding {
                OnboardingView { signUp in
                    openAuthWithSignUp = signUp
                    hasCompletedOnboarding = true
                }
            } else {
                AuthContainerView(preferSignUp: openAuthWithSignUp)
                    .id(openAuthWithSignUp)
            }
        }
        .animation(.default, value: sessionStore.session?.user.id)
        .animation(.default, value: hasCompletedOnboarding)
    }
}

#Preview {
    AppRootView()
        .environment(SessionStore())
}

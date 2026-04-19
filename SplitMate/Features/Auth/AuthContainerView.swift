import SwiftUI

struct AuthContainerView: View {
    @Environment(SessionStore.self) private var sessionStore
    @State private var mode: AuthMode

    private let preferSignUp: Bool

    enum AuthMode {
        case signIn, signUp
    }

    init(preferSignUp: Bool = false) {
        self.preferSignUp = preferSignUp
        _mode = State(initialValue: preferSignUp ? .signUp : .signIn)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer().frame(height: 12)

                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(SplitMateTheme.brandIconGradient)
                            .frame(width: 64, height: 64)
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: 30))
                            .foregroundStyle(.white.opacity(0.95))
                    }
                    .padding(.bottom, 14)

                    Text(mode == .signIn ? "Welcome back" : "Create account")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(SplitMateTheme.labelPrimary)

                    Text(mode == .signIn
                        ? "Sign in to SplitMate and\nget back to splitting."
                        : "Join SplitMate to share expenses\nwith friends and groups.")
                        .font(.subheadline)
                        .foregroundStyle(SplitMateTheme.labelSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                        .padding(.bottom, 28)

                    if let err = sessionStore.authError, !err.isEmpty {
                        Text(err)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.bottom, 12)
                    }

                    if mode == .signIn {
                        signInFields
                    } else {
                        signUpFields
                    }

                    Spacer().frame(height: 20)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 28)
            }
            .background(Color.white)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    // MARK: - Sign in (HTML-style grouped inputs)

    private var signInFields: some View {
        SignInFieldsStyled(
            onToggleSignUp: {
                sessionStore.clearAuthError()
                mode = .signUp
            }
        )
    }

    private var signUpFields: some View {
        SignUpFieldsStyled(
            onToggleSignIn: {
                sessionStore.clearAuthError()
                mode = .signIn
            }
        )
    }
}

// MARK: - Styled sign-in (APIs unchanged)

private struct SignInFieldsStyled: View {
    @Environment(SessionStore.self) private var sessionStore
    var onToggleSignUp: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Image(systemName: "envelope.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(SplitMateTheme.labelSecondary.opacity(0.5))
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 15))
                        .foregroundStyle(SplitMateTheme.labelPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)

                Divider().background(SplitMateTheme.separator)

                HStack(spacing: 10) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(SplitMateTheme.labelSecondary.opacity(0.5))
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .font(.system(size: 15))
                        .foregroundStyle(SplitMateTheme.labelPrimary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 13)
            }
            .background(SplitMateTheme.groupedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            HStack {
                Spacer()
                Button("Forgot password?") {}
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(SplitMateTheme.brandPurple)
                    .disabled(true)
                    .opacity(0.55)
            }
            .padding(.top, 10)
            .padding(.bottom, 16)

            Button {
                Task {
                    busy = true
                    defer { busy = false }
                    await sessionStore.signIn(email: email, password: password)
                }
            } label: {
                Text("Sign in")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SplitMateTheme.brandPurple)
            )
            .disabled(email.isEmpty || password.isEmpty || busy)
            .opacity(email.isEmpty || password.isEmpty || busy ? 0.45 : 1)

            // Connect with Google / Apple — set to `true` when OAuth is wired to Supabase.
            if false {
                HStack(spacing: 10) {
                    Rectangle()
                        .fill(SplitMateTheme.separator)
                        .frame(height: 0.5)
                    Text("or continue with")
                        .font(.system(size: 12))
                        .foregroundStyle(SplitMateTheme.labelSecondary)
                    Rectangle()
                        .fill(SplitMateTheme.separator)
                        .frame(height: 0.5)
                }
                .padding(.vertical, 14)

                socialPlaceholderGoogleButton()
                socialPlaceholderButton(title: "Continue with Apple", systemImage: "apple.logo", dark: true)
            }

            HStack(spacing: 4) {
                Text("Don't have an account?")
                    .foregroundStyle(SplitMateTheme.labelSecondary)
                Button("Sign up") {
                    onToggleSignUp()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SplitMateTheme.brandPurple)
            }
            .font(.system(size: 13))
            .padding(.top, 12)
        }
    }

    private func socialPlaceholderGoogleButton() -> some View {
        Button {} label: {
            HStack(spacing: 8) {
                Text("G")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(Color(red: 66 / 255, green: 133 / 255, blue: 244 / 255))
                    .frame(width: 18, height: 18)
                Text("Continue with Google")
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(SplitMateTheme.labelPrimary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SplitMateTheme.groupedBackground)
            )
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.5)
        .padding(.bottom, 10)
    }

    private func socialPlaceholderButton(title: String, systemImage: String, dark: Bool = false) -> some View {
        Button {} label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 16))
                Text(title)
                    .font(.system(size: 14, weight: .medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .foregroundStyle(dark ? Color.white : SplitMateTheme.labelPrimary)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(dark ? SplitMateTheme.labelPrimary : SplitMateTheme.groupedBackground)
            )
        }
        .buttonStyle(.plain)
        .disabled(true)
        .opacity(0.5)
        .padding(.bottom, 10)
    }
}

// MARK: - Styled sign-up

private struct SignUpFieldsStyled: View {
    @Environment(SessionStore.self) private var sessionStore
    var onToggleSignIn: () -> Void

    @State private var email = ""
    @State private var password = ""
    @State private var username = ""
    @State private var busy = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                fieldRow(icon: "person.fill", content: {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 15))
                })
                Divider().background(SplitMateTheme.separator)
                fieldRow(icon: "envelope.fill", content: {
                    TextField("Email", text: $email)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .font(.system(size: 15))
                })
                Divider().background(SplitMateTheme.separator)
                fieldRow(icon: "lock.fill", content: {
                    SecureField("Password", text: $password)
                        .textContentType(.newPassword)
                        .font(.system(size: 15))
                })
            }
            .background(SplitMateTheme.groupedBackground)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

            Button {
                Task {
                    busy = true
                    defer { busy = false }
                    await sessionStore.signUp(email: email, password: password, username: username)
                }
            } label: {
                Text("Create account")
                    .font(.system(size: 16, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(SplitMateTheme.brandPurple)
            )
            .padding(.top, 20)
            .disabled(email.isEmpty || password.isEmpty || username.isEmpty || busy)
            .opacity(email.isEmpty || password.isEmpty || username.isEmpty || busy ? 0.45 : 1)

            HStack(spacing: 4) {
                Text("Already have an account?")
                    .foregroundStyle(SplitMateTheme.labelSecondary)
                Button("Sign in") {
                    onToggleSignIn()
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SplitMateTheme.brandPurple)
            }
            .font(.system(size: 13))
            .padding(.top, 12)
        }
    }

    private func fieldRow<C: View>(icon: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(SplitMateTheme.labelSecondary.opacity(0.5))
                .frame(width: 16)
            content()
                .foregroundStyle(SplitMateTheme.labelPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
    }
}

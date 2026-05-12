import AuthenticationServices
import SwiftUI

/// First-run Sign In with Apple screen. On success, exchanges the Apple identity
/// token with the DripAdvisor backend for a session JWT stored in `AuthStore`.
struct SignInView: View {
    let auth: AuthStore
    let api: DripAPI

    @State private var error: String?
    @State private var isSigningIn = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Text("DripAdvisor")
                    .font(.system(size: 38, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.textPrimary)

                Text("Your closet, but smarter.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)

                Spacer()

                SignInWithAppleButton(
                    onRequest: { req in req.requestedScopes = [.email] },
                    onCompletion: handleCompletion
                )
                .signInWithAppleButtonStyle(.black)
                .frame(height: 52)
                .cornerRadius(14)
                .disabled(isSigningIn)
                .opacity(isSigningIn ? 0.5 : 1)

                #if DEBUG
                Button(action: continueAsDev) {
                    Text("Continue as Dev User")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .underline()
                }
                #endif

                if let error {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(24)
        }
    }

    #if DEBUG
    private func continueAsDev() {
        auth.signIn(
            token: "dev-bypass-token",
            userID: UUID(uuidString: "DE7E0000-0000-0000-0000-000000000001") ?? UUID(),
            expiresAt: Date().addingTimeInterval(60 * 60 * 24 * 30)
        )
    }
    #endif

    private func handleCompletion(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .failure(let e):
            error = e.localizedDescription
        case .success(let auth):
            guard
                let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let idToken = String(data: tokenData, encoding: .utf8)
            else {
                error = "Missing identity token"
                return
            }
            isSigningIn = true
            Task {
                defer { isSigningIn = false }
                do {
                    let resp = try await api.appleSignIn(identityToken: idToken)
                    self.auth.signIn(
                        token: resp.session,
                        userID: resp.user.id,
                        expiresAt: resp.expiresAt
                    )
                    self.error = nil
                } catch {
                    self.error = error.localizedDescription
                }
            }
        }
    }
}

import AuthenticationServices
import CryptoKit
import SwiftUI

/// Sign in with Apple, on brand.
///
/// The nonce matters: we generate a random string, send Apple its SHA-256, and the
/// backend compares that hash against the one Apple echoes into the identity token.
/// Without it, a token captured from one sign-in could be replayed into another
/// session.
struct SignInView: View {
    @EnvironmentObject private var auth: Auth
    @State private var busy = false
    @State private var error: String?
    /// Raw nonce for the in-flight request. Apple only ever sees its hash.
    @State private var rawNonce = ""

    var body: some View {
        ZStack {
            AuroraBackground(tint: Brand.cyan)

            VStack(spacing: 0) {
                Spacer()
                VoiceOrb(state: .idle, level: 0)
                    .frame(width: 200, height: 200)

                VStack(spacing: 8) {
                    HStack(spacing: 0) {
                        Text("WeMend").foregroundStyle(.white)
                        Text("AI").foregroundStyle(
                            LinearGradient(gradient: Brand.sweep,
                                           startPoint: .leading, endPoint: .trailing))
                    }
                    .font(.system(size: 34, weight: .bold))
                    Text("LISTEN · UNDERSTAND · HEAL")
                        .font(.system(size: 10, weight: .semibold))
                        .tracking(2.2)
                        .foregroundStyle(Brand.teal.opacity(0.8))
                }
                .padding(.top, 28)

                Text("A calm place to be heard —\nand to be understood by each other.")
                    .font(.system(size: 15))
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .padding(.top, 22)
                    .padding(.horizontal, 34)

                Spacer()

                SignInWithAppleButton(.signIn, onRequest: configure, onCompletion: handle)
                    .signInWithAppleButtonStyle(.white)
                    .frame(height: 52)
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .padding(.horizontal, 28)
                    .disabled(busy)
                    .opacity(busy ? 0.5 : 1)

                if busy {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Signing in…").font(.caption)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                    .padding(.top, 14)
                }

                Text("We never repeat anything to your partner\nunless you approve the exact words first.")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)
                    .padding(.top, 20)
                    .padding(.bottom, 34)

                if let error {
                    Text(error).font(.caption).foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 28).padding(.bottom, 20)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Apple flow

    private func configure(_ request: ASAuthorizationAppleIDRequest) {
        rawNonce = Self.randomNonce()
        request.requestedScopes = [.fullName, .email]
        // Apple echoes this hash into the identity token; the backend compares it.
        request.nonce = Self.sha256(rawNonce)
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        error = nil
        switch result {
        case let .failure(err):
            // Cancelling is not an error worth shouting about.
            if (err as? ASAuthorizationError)?.code == .canceled { return }
            error = err.localizedDescription

        case let .success(authorization):
            guard let cred = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let identityToken = cred.identityToken,
                  let identity = String(data: identityToken, encoding: .utf8) else {
                error = "Apple did not return an identity token."
                return
            }
            // authorizationCode is single-use and only arrives here. The backend needs
            // it to obtain a refresh token, which is the only thing that can later
            // revoke this account — required for App Store account deletion.
            let code = cred.authorizationCode.flatMap { String(data: $0, encoding: .utf8) }
            // The full name arrives ONLY on the very first authorization, ever. If we
            // don't forward it now it is gone permanently, including across reinstalls.
            let name = [cred.fullName?.givenName, cred.fullName?.familyName]
                .compactMap { $0 }.joined(separator: " ")

            Task { await send(identity: identity, code: code,
                              name: name.isEmpty ? nil : name) }
        }
    }

    private func send(identity: String, code: String?, name: String?) async {
        busy = true
        defer { busy = false }
        guard let url = URL(string: Config.defaultServerURL) else { return }
        do {
            let client = VoiceClient(baseURL: url)
            let res = try await client.signInWithApple(
                identityToken: identity, authorizationCode: code,
                rawNonce: rawNonce, fullName: name,
                deviceName: UIDevice.current.name)
            auth.store(token: res.token, user: res.user)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: nonce

    private static func randomNonce(length: Int = 32) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return bytes.map { String(format: "%02x", $0) }.joined()
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

import Foundation
import Security

/// Keychain storage for the session token.
///
/// Not `UserDefaults`: that is a plist in the app container, readable from a backup
/// and not protected by the passcode. `ContentView` uses `@AppStorage` for the server
/// URL, which is fine for a URL — this exists so that pattern is never extended to a
/// bearer token.
enum Keychain {
    private static let service = "ai.wemend.session"

    /// `afterFirstUnlock` rather than `whenUnlocked`: the app may need to refresh a
    /// relay in the background, but the token should still be unreadable on a device
    /// that has not been unlocked since boot.
    private static let accessible = kSecAttrAccessibleAfterFirstUnlock

    static func set(_ value: String, for key: String) {
        let data = Data(value.utf8)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)          // upsert
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = accessible
        SecItemAdd(query as CFDictionary, nil)
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(_ key: String) {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ] as CFDictionary)
    }
}

/// The signed-in session, persisted across launches.
@MainActor
final class Auth: ObservableObject {
    @Published private(set) var token: String?
    @Published private(set) var displayName: String?
    @Published private(set) var onboardingComplete = false
    @Published private(set) var hasPartner = false

    private let tokenKey = "bearer"

    var isSignedIn: Bool { token != nil }

    init() { token = Keychain.get(tokenKey) }

    func store(token: String, user: AuthedUser) {
        Keychain.set(token, for: tokenKey)
        self.token = token
        apply(user)
    }

    func apply(_ user: AuthedUser) {
        displayName = user.displayName
        onboardingComplete = user.onboardingComplete
        hasPartner = user.hasPartner
    }

    func markOnboardingComplete() { onboardingComplete = true }

    /// Re-read state from the server on launch. The Keychain token survives reinstall
    /// of nothing, but onboarding state lives server-side, so a fresh install with a
    /// valid token must not be sent through onboarding again.
    func refresh() async {
        guard let token, let url = URL(string: Config.defaultServerURL) else { return }
        do {
            let p = try await ProfileClient(baseURL: url, bearer: token).get()
            displayName = p.displayName
            onboardingComplete = p.onboardingComplete
        } catch ClientError.signedOut {
            clear()
        } catch {
            // Offline: keep whatever we had rather than bouncing the user to sign-in.
        }
    }

    /// Clears local state. Call after a successful sign-out or account deletion, and
    /// on a 401 — a token the server has revoked is worse than no token, because the
    /// UI would keep retrying with it.
    func clear() {
        Keychain.delete(tokenKey)
        token = nil
        displayName = nil
        onboardingComplete = false
        hasPartner = false
    }
}

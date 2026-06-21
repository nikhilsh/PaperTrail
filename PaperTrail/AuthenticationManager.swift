import Foundation
import AuthenticationServices

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// Manages Sign in with Apple authentication state.
@Observable
@MainActor
final class AuthenticationManager {
    var isSignedIn = false
    var userID: String?
    var userName: String?
    var userEmail: String?
    /// A name the user set themselves. Apple only returns the real name on the
    /// first consent, so this is the only way to show a name on re-sign-ins.
    var customName: String?

    /// The best name we have, or nil if we genuinely don't know one.
    var resolvedName: String? {
        if let customName = customName?.nilIfBlank { return customName }
        if let userName = userName?.nilIfBlank { return userName }
        if let userEmail = userEmail?.nilIfBlank {
            let prefix = userEmail.split(separator: "@").first.map(String.init) ?? userEmail
            return prefix.replacingOccurrences(of: ".", with: " ").capitalized
        }
        return nil
    }

    var displayName: String {
        resolvedName ?? "Apple User"
    }

    /// True when we have no real name and are falling back to a placeholder.
    var hasName: Bool { resolvedName != nil }

    /// Persist a user-entered display name (pass empty to clear).
    func setDisplayName(_ name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        customName = trimmed.isEmpty ? nil : trimmed
        if let customName {
            UserDefaults.standard.set(customName, forKey: customNameKey)
        } else {
            UserDefaults.standard.removeObject(forKey: customNameKey)
        }
    }

    private let userIDKey = "appleUserID"
    private let userNameKey = "appleUserName"
    private let userEmailKey = "appleUserEmail"
    private let customNameKey = "appleCustomName"

    init() {
        // Restore from Keychain/UserDefaults
        userID = UserDefaults.standard.string(forKey: userIDKey)
        userName = UserDefaults.standard.string(forKey: userNameKey)
        userEmail = UserDefaults.standard.string(forKey: userEmailKey)
        customName = UserDefaults.standard.string(forKey: customNameKey)
        isSignedIn = userID != nil
    }

    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }

            userID = credential.user
            UserDefaults.standard.set(credential.user, forKey: userIDKey)

            let resolvedName = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0?.nilIfBlank }
                .joined(separator: " ")
                .nilIfBlank
                ?? userName?.nilIfBlank
                ?? userEmail?.nilIfBlank?.split(separator: "@").first.map(String.init)?.replacingOccurrences(of: ".", with: " ").capitalized

            if let resolvedName {
                userName = resolvedName
                UserDefaults.standard.set(resolvedName, forKey: userNameKey)
            }

            let resolvedEmail = credential.email?.nilIfBlank ?? userEmail?.nilIfBlank
            if let resolvedEmail {
                userEmail = resolvedEmail
                UserDefaults.standard.set(resolvedEmail, forKey: userEmailKey)
            }

            isSignedIn = true

        case .failure(let error):
            print("Sign in with Apple failed: \(error)")
        }
    }

    func signOut() {
        userID = nil
        userName = nil
        userEmail = nil
        customName = nil
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: userIDKey)
        UserDefaults.standard.removeObject(forKey: userNameKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
        UserDefaults.standard.removeObject(forKey: customNameKey)
    }

    /// Check if the Apple ID credential is still valid.
    func checkCredentialState() async {
        guard let userID else { return }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: userID)
            if state == .revoked || state == .notFound {
                signOut()
            }
        } catch {
            print("Credential state check failed: \(error)")
        }
    }
}

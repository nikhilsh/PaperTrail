import Foundation
import AuthenticationServices

/// Manages Sign in with Apple authentication state.
@Observable
@MainActor
final class AuthenticationManager {
    var isSignedIn = false
    var userID: String?
    var userName: String?
    var userEmail: String?

    private let userIDKey = "appleUserID"
    private let userNameKey = "appleUserName"
    private let userEmailKey = "appleUserEmail"

    init() {
        // Restore from Keychain/UserDefaults
        userID = UserDefaults.standard.string(forKey: userIDKey)
        userName = UserDefaults.standard.string(forKey: userNameKey)
        userEmail = UserDefaults.standard.string(forKey: userEmailKey)
        isSignedIn = userID != nil
    }

    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }

            userID = credential.user
            UserDefaults.standard.set(credential.user, forKey: userIDKey)

            // Name and email are only provided on first sign-in
            if let fullName = credential.fullName {
                let name = [fullName.givenName, fullName.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                if !name.isEmpty {
                    userName = name
                    UserDefaults.standard.set(name, forKey: userNameKey)
                }
            }
            if let email = credential.email {
                userEmail = email
                UserDefaults.standard.set(email, forKey: userEmailKey)
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
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: userIDKey)
        UserDefaults.standard.removeObject(forKey: userNameKey)
        UserDefaults.standard.removeObject(forKey: userEmailKey)
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

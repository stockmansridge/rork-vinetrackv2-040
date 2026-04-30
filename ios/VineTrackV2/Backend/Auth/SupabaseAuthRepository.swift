import Foundation
import Supabase

final class SupabaseAuthRepository: AuthRepository {
    private let provider: SupabaseClientProvider

    init(provider: SupabaseClientProvider = .shared) {
        self.provider = provider
    }

    var currentUserId: UUID? {
        provider.client.auth.currentUser?.id
    }

    func restoreSession() async throws -> AppUser? {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard let session = provider.client.auth.currentSession else { return nil }
        return appUser(from: session.user)
    }

    func signInWithEmail(email: String, password: String) async throws -> AppUser {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.auth.signIn(email: email, password: password)
        let session = try await provider.client.auth.session
        return appUser(from: session.user)
    }

    func signUpWithEmail(name: String, email: String, password: String) async throws -> AppUser? {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let response = try await provider.client.auth.signUp(email: email, password: password)
        return appUser(from: response.user, fallbackEmail: email, fallbackDisplayName: name)
    }

    func signOut() async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.auth.signOut()
    }

    func sendPasswordReset(email: String, redirectTo: URL?) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.auth.resetPasswordForEmail(email, redirectTo: redirectTo)
    }

    func handlePasswordRecoveryURL(_ url: URL) async throws -> AppUser {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let session = try await provider.client.auth.session(from: url)
        return appUser(from: session.user)
    }

    func verifyPasswordResetPin(email: String, pin: String) async throws -> AppUser {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.auth.verifyOTP(email: email, token: pin, type: .recovery)
        let session = try await provider.client.auth.session
        return appUser(from: session.user, fallbackEmail: email)
    }

    func updatePassword(_ newPassword: String) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client.auth.update(user: UserAttributes(password: newPassword))
    }

    func resetPasswordWithPin(email: String, pin: String, newPassword: String) async throws -> AppUser {
        let user = try await verifyPasswordResetPin(email: email, pin: pin)
        try await updatePassword(newPassword)
        return user
    }

    func signInWithApple(idToken: String, nonce: String?) async throws -> AppUser {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let credentials = OpenIDConnectCredentials(
            provider: .apple,
            idToken: idToken,
            nonce: nonce
        )
        try await provider.client.auth.signInWithIdToken(credentials: credentials)
        let session = try await provider.client.auth.session
        return appUser(from: session.user)
    }

    private func appUser(from user: User, fallbackEmail: String? = nil, fallbackDisplayName: String? = nil) -> AppUser {
        let email = user.email ?? fallbackEmail ?? ""
        return AppUser(
            id: user.id,
            email: email,
            displayName: fallbackDisplayName ?? email,
            avatarURL: nil,
            createdAt: user.createdAt
        )
    }
}

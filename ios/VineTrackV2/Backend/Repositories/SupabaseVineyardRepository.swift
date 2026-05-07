import Foundation
import Supabase

final class SupabaseVineyardRepository: VineyardRepositoryProtocol {
    private let provider: SupabaseClientProvider

    init(provider: SupabaseClientProvider = .shared) {
        self.provider = provider
    }

    func listMyVineyards() async throws -> [BackendVineyard] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        return try await provider.client
            .from("vineyards")
            .select()
            .is("deleted_at", value: nil)
            .order("name", ascending: true)
            .execute()
            .value
    }

    func listAllAccessibleVineyards(includeDeleted: Bool) async throws -> [BackendVineyard] {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        if includeDeleted {
            return try await provider.client
                .from("vineyards")
                .select()
                .order("name", ascending: true)
                .execute()
                .value
        } else {
            return try await listMyVineyards()
        }
    }

    func createVineyard(name: String, country: String?) async throws -> BackendVineyard {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        guard provider.client.auth.currentUser != nil else { throw BackendRepositoryError.missingAuthenticatedUser }
        let vineyards: [BackendVineyard] = try await provider.client
            .rpc("create_vineyard_with_owner", params: CreateVineyardRequest(name: name, country: country))
            .execute()
            .value
        guard let vineyard = vineyards.first else { throw BackendRepositoryError.emptyResponse }
        return vineyard
    }

    /// Updates the vineyard's name and country only. Logo path is intentionally
    /// not touched here — use `updateVineyardLogoPath` for that, otherwise
    /// renaming a vineyard would wipe its synced logo.
    func updateVineyard(_ vineyard: BackendVineyard) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client
            .from("vineyards")
            .update(VineyardUpdate(name: vineyard.name, country: vineyard.country))
            .eq("id", value: vineyard.id.uuidString)
            .execute()
    }

    /// Sets or clears the vineyard's `logo_path` and bumps `logo_updated_at`
    /// so other devices know to refetch the logo. Returns the new
    /// `logo_updated_at` value as reported by the database.
    @discardableResult
    func updateVineyardLogoPath(vineyardId: UUID, logoPath: String?) async throws -> Date? {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let now = Date()
        let response: [VineyardLogoUpdateResponse] = try await provider.client
            .from("vineyards")
            .update(VineyardLogoUpdate(logoPath: logoPath, logoUpdatedAt: now))
            .eq("id", value: vineyardId.uuidString)
            .select("logo_updated_at")
            .execute()
            .value
        return response.first?.logoUpdatedAt ?? now
    }

    func softDeleteVineyard(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client
            .from("vineyards")
            .update(VineyardSoftDelete(deletedAt: Date()))
            .eq("id", value: id.uuidString)
            .execute()
    }

    func archiveVineyard(id: UUID) async throws {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        try await provider.client
            .rpc("archive_vineyard", params: ArchiveVineyardRequest(vineyardId: id))
            .execute()
    }

    func accountDeletionPreflight() async throws -> AccountDeletionPreflight {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let result: AccountDeletionPreflight = try await provider.client
            .rpc("account_deletion_preflight")
            .execute()
            .value
        return result
    }

    func submitAccountDeletionRequest(reason: String?) async throws -> AccountDeletionRequestResult {
        guard provider.isConfigured else { throw BackendRepositoryError.missingSupabaseConfiguration }
        let result: AccountDeletionRequestResult = try await provider.client
            .rpc("submit_account_deletion_request", params: SubmitDeletionRequest(reason: reason))
            .execute()
            .value
        return result
    }
}

nonisolated private struct ArchiveVineyardRequest: Encodable, Sendable {
    let vineyardId: UUID

    enum CodingKeys: String, CodingKey {
        case vineyardId = "p_vineyard_id"
    }
}

nonisolated private struct SubmitDeletionRequest: Encodable, Sendable {
    let reason: String?

    enum CodingKeys: String, CodingKey {
        case reason = "p_reason"
    }
}

nonisolated private struct CreateVineyardRequest: Encodable, Sendable {
    let name: String
    let country: String?

    enum CodingKeys: String, CodingKey {
        case name = "p_name"
        case country = "p_country"
    }
}

nonisolated private struct VineyardUpdate: Encodable, Sendable {
    let name: String
    let country: String?
}

nonisolated private struct VineyardLogoUpdate: Encodable, Sendable {
    let logoPath: String?
    let logoUpdatedAt: Date

    enum CodingKeys: String, CodingKey {
        case logoPath = "logo_path"
        case logoUpdatedAt = "logo_updated_at"
    }
}

nonisolated private struct VineyardLogoUpdateResponse: Decodable, Sendable {
    let logoUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case logoUpdatedAt = "logo_updated_at"
    }
}

nonisolated private struct VineyardSoftDelete: Encodable, Sendable {
    let deletedAt: Date

    enum CodingKeys: String, CodingKey {
        case deletedAt = "deleted_at"
    }
}

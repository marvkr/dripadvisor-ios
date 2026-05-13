import Foundation
import SwiftUI

private struct DripAPIKey: EnvironmentKey {
    static let defaultValue: DripAPI? = nil
}

extension EnvironmentValues {
    var dripAPI: DripAPI? {
        get { self[DripAPIKey.self] }
        set { self[DripAPIKey.self] = newValue }
    }
}

/// High-level endpoint DTOs + thin wrapper calls. Mirrors backend/internal/httpapi.
struct DripAPI: Sendable {
    let client: APIClient

    // MARK: Apple Sign In

    struct AppleSignInRequest: Encodable {
        let identityToken: String
    }

    struct AppleSignInResponse: Decodable {
        let session: String
        let expiresAt: Date
        let user: UserDTO
    }

    struct UserDTO: Decodable, Sendable {
        let id: UUID
        let email: String?
        let username: String?
        let displayName: String?
        let avatarUrl: String?
        let accountTier: String
    }

    func appleSignIn(identityToken: String) async throws -> AppleSignInResponse {
        try await client.post("/v1/auth/apple", body: AppleSignInRequest(identityToken: identityToken))
    }

    func me() async throws -> UserDTO {
        try await client.get("/v1/me")
    }

    // MARK: Wardrobe

    struct WardrobeItemDTO: Codable, Sendable, Identifiable {
        let id: UUID
        let name: String
        let brand: String
        let category: String
        let imageUrl: String?
        let tags: [String]
        let createdAt: Date
    }

    struct AddWardrobeRequest: Encodable {
        let name: String
        let brand: String
        let category: String
        let imageUrl: String?
        let tags: [String]
    }

    struct WardrobeListResponse: Decodable {
        let items: [WardrobeItemDTO]
    }

    func listWardrobe() async throws -> [WardrobeItemDTO] {
        let resp: WardrobeListResponse = try await client.get("/v1/wardrobe")
        return resp.items
    }

    func addWardrobe(_ req: AddWardrobeRequest) async throws -> WardrobeItemDTO {
        try await client.post("/v1/wardrobe", body: req)
    }

    func deleteWardrobe(id: UUID) async throws {
        try await client.delete("/v1/wardrobe/\(id.uuidString.lowercased())")
    }

    // MARK: Scrape (Add-from-web)

    struct ScrapeRequest: Encodable {
        let url: String
    }

    struct ScrapeResponse: Decodable, Hashable {
        let name: String?
        let brand: String?
        let imageUrl: String?
        let retailPrice: Double?
        let currency: String?
        let sourceUrl: String?
    }

    func scrapeWardrobe(url: String) async throws -> ScrapeResponse {
        try await client.post("/v1/wardrobe/scrape", body: ScrapeRequest(url: url))
    }

    // MARK: Try-On

    struct TryOnRequest: Encodable {
        let bodyPhotoBase64: String
        let bodyMime: String
        let garmentBase64: String?
        let garmentMime: String?
        let wardrobeID: UUID?
        let occasion: String?
    }

    struct TryOnResponse: Decodable {
        let compositeUrl: String
        let generatedAt: Date
    }

    func runTryOn(_ req: TryOnRequest) async throws -> TryOnResponse {
        try await client.post("/v1/tryon", body: req)
    }

    // MARK: Outfits

    struct OutfitDTO: Decodable, Sendable, Identifiable {
        let id: UUID
        let compositeImageUrl: String?
        let thumbnailUrl: String?
        let occasion: String?
        let tags: [String]
        let visibility: String
        let source: String
        let createdAt: Date
    }

    struct CreateOutfitRequest: Encodable {
        let occasion: String?
        let tags: [String]
        let visibility: String
    }

    struct OutfitListResponse: Decodable {
        let outfits: [OutfitDTO]
    }

    func listOutfits() async throws -> [OutfitDTO] {
        let resp: OutfitListResponse = try await client.get("/v1/outfits")
        return resp.outfits
    }

    func createOutfit(_ req: CreateOutfitRequest) async throws -> OutfitDTO {
        try await client.post("/v1/outfits", body: req)
    }
}

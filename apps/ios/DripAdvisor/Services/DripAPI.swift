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

    // MARK: Garment analysis (auto-fill)

    struct GarmentAnalysisDTO: Decodable, Sendable {
        let name: String
        let brand: String
        let category: String
        let colorPrimary: String
        let tags: [String]
    }

    /// Sends the BG-removed garment image to Gemini Vision via backend.
    /// Returns best-effort {name, brand, category, color, tags} — user edits later if wrong.
    func analyzeGarment(jpeg: Data) async throws -> GarmentAnalysisDTO {
        let boundary = "DripBoundary-\(UUID().uuidString)"
        guard let url = URL(string: "/v1/wardrobe/analyze", relativeTo: client.baseURL) else {
            throw APIError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let tok = client.tokenProvider() {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"garment.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await client.session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.badResponse(status: code, body: String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder.api.decode(GarmentAnalysisDTO.self, from: data)
    }

    // MARK: Avatar

    /// Uploads the user's body reference photo as multipart/form-data.
    /// Backend stores in S3 at avatars/{user_id}.jpg.
    func uploadAvatar(jpeg: Data) async throws {
        let boundary = "DripBoundary-\(UUID().uuidString)"
        guard let url = URL(string: "/v1/me/avatar", relativeTo: client.baseURL) else {
            throw APIError.badURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        if let tok = client.tokenProvider() {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"avatar.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, resp) = try await client.session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let code = (resp as? HTTPURLResponse)?.statusCode ?? -1
            throw APIError.badResponse(status: code, body: String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Streams the user's avatar bytes. Returns nil on 404.
    func fetchAvatar() async throws -> Data? {
        guard let url = URL(string: "/v1/me/avatar", relativeTo: client.baseURL) else {
            throw APIError.badURL
        }
        var req = URLRequest(url: url)
        if let tok = client.tokenProvider() {
            req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await client.session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { return nil }
        if http.statusCode == 404 { return nil }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.badResponse(status: http.statusCode, body: "")
        }
        return data
    }
}

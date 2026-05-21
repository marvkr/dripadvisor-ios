import Foundation
import UIKit

/// Runs the real try-on flow: sends the user's avatar + a garment image to
/// `/tryon`, waits for Gemini, returns the composite image data + URL.
///
/// Synchronous in v1 (single long-lived HTTPS request, ~5–60s). Locked design
/// per README "v1.1 Chat Design (locked)" — body bytes never persisted server-
/// side, no Redis-stashed body refs in v1.
struct TryOnService: Sendable {
    let api: DripAPI

    /// Long-timeout session for fetching the composite from R2. The /tryon
    /// POST itself goes through the shared APIClient (already long-timeout via
    /// scheme config).
    private static let downloadSession: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 120
        return URLSession(configuration: cfg)
    }()

    enum TryOnError: Error, LocalizedError {
        case missingAvatar
        case missingGarmentImage
        case encodingFailed
        case downloadFailed
        case server(APIError)

        var errorDescription: String? {
            switch self {
            case .missingAvatar: "Set up your avatar before generating a try-on."
            case .missingGarmentImage: "This item has no image yet."
            case .encodingFailed: "Couldn't prepare image for upload."
            case .downloadFailed: "Couldn't fetch the generated image."
            case .server(let e): e.errorDescription
            }
        }
    }

    struct Result {
        let imageData: Data
        let compositeURL: URL
    }

    /// Compose a try-on. Body + garment bytes uploaded inline (base64) so the
    /// server holds them in memory only, never on disk. Composite returned via
    /// signed R2 URL — we fetch the bytes once and hand back to the store.
    func compose(
        avatarData: Data,
        avatarMIME: String = "image/jpeg",
        garmentData: Data,
        garmentMIME: String = "image/png",
        occasion: String? = nil
    ) async throws -> Result {
        let req = DripAPI.TryOnRequest(
            bodyPhotoBase64: avatarData.base64EncodedString(),
            bodyMime: avatarMIME,
            garmentBase64: garmentData.base64EncodedString(),
            garmentMime: garmentMIME,
            wardrobeID: nil,
            occasion: occasion
        )

        let resp: DripAPI.TryOnResponse
        do {
            resp = try await api.runTryOn(req)
        } catch let e as APIError {
            throw TryOnError.server(e)
        }

        guard let url = URL(string: resp.compositeUrl) else {
            throw TryOnError.downloadFailed
        }
        let (data, response) = try await Self.downloadSession.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw TryOnError.downloadFailed
        }
        return Result(imageData: data, compositeURL: url)
    }
}

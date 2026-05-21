import Foundation
import UIKit

/// Container for whatever the iOS Share Sheet hands us. Any combination of
/// fields may be populated.
struct SharePayload: Sendable {
    var url: URL?
    var image: UIImage?
    var imageData: Data?
    var text: String?
}

/// Pending wardrobe item produced inside the Share Extension. We drop these
/// into the App Group container; the main app picks them up on next launch
/// and POSTs to /wardrobe.
struct PendingWardrobeItem: Codable, Sendable {
    let id: UUID
    let name: String
    let brand: String
    let category: String
    let source: String          // "owned" or "wishlist"
    let sourceURL: URL?
    let imageBase64: String?
    let createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        brand: String,
        category: String,
        source: String,
        sourceURL: URL? = nil,
        imageData: Data? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.category = category
        self.source = source
        self.sourceURL = sourceURL
        self.imageBase64 = imageData?.base64EncodedString()
        self.createdAt = createdAt
    }

    var imageData: Data? {
        imageBase64.flatMap { Data(base64Encoded: $0) }
    }
}

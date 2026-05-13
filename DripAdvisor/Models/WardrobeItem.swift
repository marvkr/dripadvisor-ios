import SwiftUI

enum WardrobeItemSource: String, Codable, Hashable, CaseIterable {
    case owned      // physical item in user's closet
    case wishlist   // saved from web/Instagram, not owned yet

    var displayName: String {
        switch self {
        case .owned: "Closet"
        case .wishlist: "Wishlist"
        }
    }
}

struct WardrobeItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var brand: String
    var category: GarmentCategory
    var imageData: Data?
    var tryOnImageData: Data?
    var createdAt: Date

    // Source distinction — drives UX (Buy CTA vs Mark Worn CTA).
    var source: WardrobeItemSource

    // Web-origin metadata. Populated when item came from a URL.
    var sourceURL: URL?
    var retailPrice: Double?
    var currency: String?

    // Owned-item metadata.
    var size: String?
    var color: String?       // free-text or hex
    var material: String?
    var pricePaid: Double?
    var tags: [String]
    var lastWornAt: Date?
    var wearCount: Int

    init(
        id: UUID = UUID(),
        name: String,
        brand: String,
        category: GarmentCategory,
        imageData: Data? = nil,
        tryOnImageData: Data? = nil,
        createdAt: Date = .now,
        source: WardrobeItemSource = .owned,
        sourceURL: URL? = nil,
        retailPrice: Double? = nil,
        currency: String? = nil,
        size: String? = nil,
        color: String? = nil,
        material: String? = nil,
        pricePaid: Double? = nil,
        tags: [String] = [],
        lastWornAt: Date? = nil,
        wearCount: Int = 0
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.category = category
        self.imageData = imageData
        self.tryOnImageData = tryOnImageData
        self.createdAt = createdAt
        self.source = source
        self.sourceURL = sourceURL
        self.retailPrice = retailPrice
        self.currency = currency
        self.size = size
        self.color = color
        self.material = material
        self.pricePaid = pricePaid
        self.tags = tags
        self.lastWornAt = lastWornAt
        self.wearCount = wearCount
    }

    var uiImage: UIImage? {
        imageData.flatMap { UIImage(data: $0) }
    }

    var tryOnUIImage: UIImage? {
        tryOnImageData.flatMap { UIImage(data: $0) }
    }

    /// Days since last worn (for "haven't worn in 47 days" badge). nil for
    /// wishlist items or never-worn owned items.
    var daysSinceWorn: Int? {
        guard let lastWornAt else { return nil }
        return Calendar.current.dateComponents([.day], from: lastWornAt, to: .now).day
    }
}

import SwiftUI

struct WardrobeItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var brand: String
    var category: GarmentCategory
    var imageData: Data?
    var tryOnImageData: Data?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        brand: String,
        category: GarmentCategory,
        imageData: Data? = nil,
        tryOnImageData: Data? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.brand = brand
        self.category = category
        self.imageData = imageData
        self.tryOnImageData = tryOnImageData
        self.createdAt = createdAt
    }

    var uiImage: UIImage? {
        imageData.flatMap { UIImage(data: $0) }
    }

    var tryOnUIImage: UIImage? {
        tryOnImageData.flatMap { UIImage(data: $0) }
    }
}

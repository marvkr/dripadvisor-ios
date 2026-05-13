import Foundation

struct Outfit: Identifiable, Hashable {
    let id: UUID
    var name: String
    var occasion: String
    var topID: UUID?
    var bottomID: UUID?
    var shoesID: UUID?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        occasion: String = "",
        topID: UUID? = nil,
        bottomID: UUID? = nil,
        shoesID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name
        self.occasion = occasion
        self.topID = topID
        self.bottomID = bottomID
        self.shoesID = shoesID
        self.createdAt = createdAt
    }
}

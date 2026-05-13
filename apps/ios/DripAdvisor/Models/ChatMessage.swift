import Foundation

enum ChatRole: String, Codable {
    case user, stylist
}

struct ChatMessage: Identifiable, Hashable {
    let id: UUID
    let role: ChatRole
    var text: String
    var suggestedItemIDs: [UUID]
    let timestamp: Date

    init(
        id: UUID = UUID(),
        role: ChatRole,
        text: String,
        suggestedItemIDs: [UUID] = [],
        timestamp: Date = .now
    ) {
        self.id = id
        self.role = role
        self.text = text
        self.suggestedItemIDs = suggestedItemIDs
        self.timestamp = timestamp
    }
}

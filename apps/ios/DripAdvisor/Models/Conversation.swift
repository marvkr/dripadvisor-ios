import Foundation

/// A chat thread. Mirrors `db.Chat` on the backend.
/// Named "Conversation" to avoid colliding with the older local-only
/// `ChatMessage` type used in the v1 StyleAgentView stub.
struct Conversation: Identifiable, Hashable, Sendable {
    let id: UUID
    var type: ConversationType
    var name: String?
    var iconURL: URL?
    var createdBy: UUID?
    var lastMessageAt: Date?
    var lastMessagePreview: String?
    var createdAt: Date
    var updatedAt: Date

    var displayTitle: String {
        name ?? (type == .direct ? "Direct" : "Group")
    }
}

enum ConversationType: String, Codable, Hashable, Sendable {
    case direct
    case group
}

struct ConversationMember: Hashable, Sendable {
    let userID: UUID?
    let agentID: UUID?
    let role: MemberRole
    let lastReadSeq: Int64
    let sharesWardrobe: Bool

    var isAgent: Bool { agentID != nil }
}

enum MemberRole: String, Codable, Hashable, Sendable {
    case admin
    case member
}

/// A single message in a conversation. Mirrors `db.Message`.
struct ConversationMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let chatID: UUID
    let senderUserID: UUID?
    let senderAgentID: UUID?
    let seq: Int64
    let body: String?
    let attachmentType: AttachmentKind?
    let attachmentID: UUID?
    let replyToID: UUID?
    let createdAt: Date
    let editedAt: Date?
    let deletedAt: Date?

    var isAgent: Bool { senderAgentID != nil }
    var isDeleted: Bool { deletedAt != nil }
}

enum AttachmentKind: String, Codable, Hashable, Sendable {
    case outfit
    case item
    case image
    case link
}

struct MessageReaction: Hashable, Sendable {
    let userID: UUID
    let emoji: String
    let createdAt: Date
}

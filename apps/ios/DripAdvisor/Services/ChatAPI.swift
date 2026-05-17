import Foundation

/// REST endpoints for chats. Pairs with `ChatSocket` for live receive.
struct ChatAPI: Sendable {
    let client: APIClient

    // MARK: list / create

    struct ChatDTO: Decodable {
        let id: UUID
        let type: String
        let name: String?
        let iconUrl: URL?
        let createdBy: UUID?
        let lastMessageAt: Date?
        let lastMessagePreview: String?
        let createdAt: Date
        let updatedAt: Date
    }

    struct ChatsResponse: Decodable { let chats: [ChatDTO] }

    func listChats() async throws -> [Conversation] {
        let resp: ChatsResponse = try await client.get("/v1/chats")
        return resp.chats.map(Self.toConversation)
    }

    struct CreateChatRequest: Encodable {
        let type: String
        let name: String?
        let participantIds: [UUID]
        let agentIds: [UUID]?
    }

    func createChat(type: ConversationType, name: String?, participants: [UUID], agents: [UUID] = []) async throws -> Conversation {
        let dto: ChatDTO = try await client.post(
            "/v1/chats",
            body: CreateChatRequest(type: type.rawValue, name: name, participantIds: participants, agentIds: agents.isEmpty ? nil : agents)
        )
        return Self.toConversation(dto)
    }

    /// Idempotent — backend returns the existing direct stylist chat or creates one.
    func ensureStylistDirect() async throws -> Conversation {
        let dto: ChatDTO = try await client.post(
            "/v1/chats/ensure-stylist",
            body: Empty()
        )
        return Self.toConversation(dto)
    }

    // MARK: messages

    struct MessageDTO: Decodable {
        let id: UUID
        let chatId: UUID
        let senderUserId: UUID?
        let senderAgentId: UUID?
        let seq: Int64
        let body: String?
        let attachmentType: String?
        let attachmentId: UUID?
        let replyToId: UUID?
        let createdAt: Date
        let editedAt: Date?
        let deletedAt: Date?
    }

    struct MessagesResponse: Decodable {
        let messages: [MessageDTO]
        // reactions keyed by message id; ignored in PR4 v0
    }

    func listMessages(chatID: UUID, afterSeq: Int64 = 0, limit: Int = 50) async throws -> [ConversationMessage] {
        let resp: MessagesResponse = try await client.get(
            "/v1/chats/\(chatID.uuidString.lowercased())/messages?after_seq=\(afterSeq)&limit=\(limit)"
        )
        return resp.messages.map(Self.toMessage)
    }

    struct SendMessageRequest: Encodable {
        let body: String?
        let attachmentType: String?
        let attachmentId: UUID?
        let replyToId: UUID?
    }

    func sendMessage(chatID: UUID, body: String) async throws -> ConversationMessage {
        let dto: MessageDTO = try await client.post(
            "/v1/chats/\(chatID.uuidString.lowercased())/messages",
            body: SendMessageRequest(body: body, attachmentType: nil, attachmentId: nil, replyToId: nil)
        )
        return Self.toMessage(dto)
    }

    // MARK: read receipt

    struct ReadRequest: Encodable { let seq: Int64 }

    func setRead(chatID: UUID, seq: Int64) async throws {
        let _: Empty = try await client.post(
            "/v1/chats/\(chatID.uuidString.lowercased())/read",
            body: ReadRequest(seq: seq)
        )
    }

    // MARK: mapping

    private static func toConversation(_ d: ChatDTO) -> Conversation {
        Conversation(
            id: d.id,
            type: ConversationType(rawValue: d.type) ?? .direct,
            name: d.name,
            iconURL: d.iconUrl,
            createdBy: d.createdBy,
            lastMessageAt: d.lastMessageAt,
            lastMessagePreview: d.lastMessagePreview,
            createdAt: d.createdAt,
            updatedAt: d.updatedAt
        )
    }

    private static func toMessage(_ d: MessageDTO) -> ConversationMessage {
        ConversationMessage(
            id: d.id,
            chatID: d.chatId,
            senderUserID: d.senderUserId,
            senderAgentID: d.senderAgentId,
            seq: d.seq,
            body: d.body,
            attachmentType: d.attachmentType.flatMap(AttachmentKind.init(rawValue:)),
            attachmentID: d.attachmentId,
            replyToID: d.replyToId,
            createdAt: d.createdAt,
            editedAt: d.editedAt,
            deletedAt: d.deletedAt
        )
    }
}

import Foundation
import Observation

/// App-wide chat state. Holds the user's list of conversations and a
/// per-conversation message buffer. Drains the WebSocket on connect and
/// merges incoming `message.new` envelopes into the right buffer.
@MainActor
@Observable
final class ChatStore {
    var conversations: [Conversation] = []
    var messagesByChat: [UUID: [ConversationMessage]] = [:]
    var loading: Bool = false
    var error: String?

    private let api: ChatAPI
    private let socket: ChatSocket
    private var socketDrainTask: Task<Void, Never>?

    init(api: ChatAPI, socket: ChatSocket) {
        self.api = api
        self.socket = socket
    }

    func start() {
        socket.connect()
        socketDrainTask?.cancel()
        socketDrainTask = Task { [weak self] in
            guard let self else { return }
            for await env in socket.messages {
                await self.handleEnvelope(env)
            }
        }
        Task {
            _ = try? await api.ensureStylistDirect()
            await refreshConversations()
        }
    }

    /// Idempotent — returns existing stylist chat id or creates one.
    /// Refreshes the conversation list so the new row shows up immediately.
    func openOrCreateStylistChat() async -> UUID? {
        do {
            let chat = try await api.ensureStylistDirect()
            await refreshConversations()
            return chat.id
        } catch {
            self.error = error.localizedDescription
            return nil
        }
    }

    func stop() {
        socket.disconnect()
        socketDrainTask?.cancel()
        socketDrainTask = nil
    }

    // MARK: refresh

    func refreshConversations() async {
        loading = true
        defer { loading = false }
        do {
            conversations = try await api.listChats()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func loadMessages(for chatID: UUID) async {
        do {
            let msgs = try await api.listMessages(chatID: chatID)
            messagesByChat[chatID] = msgs
            if let last = msgs.last {
                try? await api.setRead(chatID: chatID, seq: last.seq)
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: send

    func send(_ body: String, to chatID: UUID) async {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            let msg = try await api.sendMessage(chatID: chatID, body: trimmed)
            // Optimistically append; the WS echo from server is deduped by id below.
            appendIfNew(msg)
        } catch {
            self.error = error.localizedDescription
        }
    }

    // MARK: WS

    private func handleEnvelope(_ env: ChatSocket.Envelope) async {
        switch env {
        case .messageNew(let m):
            appendIfNew(m)
            // Bump the conversation row preview + lastMessageAt locally so
            // the chat list updates without a refresh.
            if let idx = conversations.firstIndex(where: { $0.id == m.chatID }) {
                conversations[idx].lastMessageAt = m.createdAt
                conversations[idx].lastMessagePreview = m.body
                let row = conversations.remove(at: idx)
                conversations.insert(row, at: 0)
            }
        case .unknown:
            break
        }
    }

    private func appendIfNew(_ m: ConversationMessage) {
        var arr = messagesByChat[m.chatID] ?? []
        if arr.contains(where: { $0.id == m.id }) { return }
        arr.append(m)
        arr.sort { $0.seq < $1.seq }
        messagesByChat[m.chatID] = arr
    }
}

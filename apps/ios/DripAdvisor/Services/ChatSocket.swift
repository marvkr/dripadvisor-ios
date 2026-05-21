import Foundation

/// Live receive for chat events. Connects to `/ws` with the JWT in the
/// Authorization header, surfaces incoming messages as an AsyncStream.
///
/// Reconnect policy: on any read error, wait the backoff window then retry
/// until cancelled. Heartbeats are owned by `URLSessionWebSocketTask` itself
/// — the server pings every 10s per the locked v1.1 design and the system
/// auto-pongs.
@MainActor
final class ChatSocket {
    private let baseURL: URL
    private let token: () -> String?
    private let session = URLSession(configuration: .default)
    private var task: URLSessionWebSocketTask?
    private var reconnectTask: Task<Void, Never>?

    /// Continuation for the public stream of inbound envelopes.
    private var continuation: AsyncStream<Envelope>.Continuation?
    let messages: AsyncStream<Envelope>

    init(baseURL: URL, token: @escaping () -> String?) {
        self.baseURL = baseURL
        self.token = token
        var cont: AsyncStream<Envelope>.Continuation!
        self.messages = AsyncStream { cont = $0 }
        self.continuation = cont
    }

    enum Envelope: Sendable {
        case messageNew(ConversationMessage)
        case unknown(String)
    }

    func connect() {
        guard reconnectTask == nil else { return }
        reconnectTask = Task { [weak self] in
            var attempt = 0
            while !Task.isCancelled {
                await self?.openOnce()
                attempt += 1
                let backoff = min(Double(attempt) * 1.5, 15)
                try? await Task.sleep(for: .seconds(backoff))
            }
        }
    }

    func disconnect() {
        reconnectTask?.cancel()
        reconnectTask = nil
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    private func openOnce() async {
        guard let tok = token() else {
            try? await Task.sleep(for: .seconds(2))
            return
        }
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else { return }
        let scheme = components.scheme
        components.scheme = (scheme == "https") ? "wss" : "ws"
        components.path = "/ws"
        guard let wsURL = components.url else { return }

        var req = URLRequest(url: wsURL)
        req.setValue("Bearer \(tok)", forHTTPHeaderField: "Authorization")
        let task = session.webSocketTask(with: req)
        self.task = task
        task.resume()
        await readLoop(task)
    }

    private func readLoop(_ task: URLSessionWebSocketTask) async {
        while !Task.isCancelled {
            do {
                let m = try await task.receive()
                handle(m)
            } catch {
                return
            }
        }
    }

    private func handle(_ m: URLSessionWebSocketTask.Message) {
        let data: Data
        switch m {
        case .data(let d): data = d
        case .string(let s): data = Data(s.utf8)
        @unknown default: return
        }
        do {
            let env = try JSONDecoder.api.decode(WireEnvelope.self, from: data)
            switch env.type {
            case "message.new":
                if let payload = env.message {
                    continuation?.yield(.messageNew(payload.toModel()))
                }
            default:
                continuation?.yield(.unknown(env.type))
            }
        } catch {
            continuation?.yield(.unknown(String(data: data, encoding: .utf8) ?? ""))
        }
    }
}

// MARK: - Wire format (mirrors backend's PublishChat envelope)

private struct WireEnvelope: Decodable {
    let type: String
    let message: WireMessage?
}

private struct WireMessage: Decodable {
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

    func toModel() -> ConversationMessage {
        ConversationMessage(
            id: id,
            chatID: chatId,
            senderUserID: senderUserId,
            senderAgentID: senderAgentId,
            seq: seq,
            body: body,
            attachmentType: attachmentType.flatMap(AttachmentKind.init(rawValue:)),
            attachmentID: attachmentId,
            replyToID: replyToId,
            createdAt: createdAt,
            editedAt: editedAt,
            deletedAt: deletedAt
        )
    }
}

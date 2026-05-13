import Foundation
import Observation
import os

@MainActor
@Observable
final class AuthStore {
    struct Session: Codable, Sendable, Equatable {
        let token: String
        let expiresAt: Date
        let userID: UUID
    }

    private static let service = "com.dripadvisor.DripAdvisor"
    private static let sessionAccount = "session"

    private(set) var session: Session?

    var isAuthenticated: Bool { session != nil }

    private let tokenStorage = OSAllocatedUnfairLock<String?>(initialState: nil)

    private func setSession(_ next: Session?) {
        session = next
        tokenStorage.withLock { $0 = next?.token }
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init() {
        if let json = KeychainHelper.read(service: Self.service, account: Self.sessionAccount),
           let data = json.data(using: .utf8),
           let decoded = try? Self.decoder.decode(Session.self, from: data) {
            setSession(decoded)
        }
    }

    func signIn(token: String, userID: UUID, expiresAt: Date) {
        let next = Session(token: token, expiresAt: expiresAt, userID: userID)
        setSession(next)
        if let encoded = try? Self.encoder.encode(next),
           let json = String(data: encoded, encoding: .utf8) {
            KeychainHelper.save(json, service: Self.service, account: Self.sessionAccount)
        }
    }

    func signOut() {
        setSession(nil)
        KeychainHelper.delete(service: Self.service, account: Self.sessionAccount)
    }

    nonisolated var tokenProvider: @Sendable () -> String? {
        let storage = tokenStorage
        return { storage.withLock { $0 } }
    }
}

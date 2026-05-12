import Testing
import Foundation
@testable import DripAdvisor

@MainActor
@Suite("AuthStore", .serialized)
struct AuthStoreTests {

    @Test("fresh AuthStore is unauthenticated")
    func freshIsUnauthenticated() {
        // Delete any prior session first to ensure a clean slate.
        KeychainHelper.delete(service: "com.dripadvisor.DripAdvisor", account: "session")
        let store = AuthStore()
        #expect(store.isAuthenticated == false)
        #expect(store.session == nil)
    }

    @Test("signIn persists + tokenProvider returns the token")
    func signInPersists() async {
        KeychainHelper.delete(service: "com.dripadvisor.DripAdvisor", account: "session")
        let store = AuthStore()
        let uid = UUID()
        let exp = Date().addingTimeInterval(3600)
        store.signIn(token: "tok_xyz", userID: uid, expiresAt: exp)

        #expect(store.isAuthenticated == true)
        #expect(store.session?.userID == uid)
        #expect(store.session?.token == "tok_xyz")
        #expect(store.tokenProvider() == "tok_xyz")

        // Reloading picks up persisted value.
        let reloaded = AuthStore()
        #expect(reloaded.session?.token == "tok_xyz")
        #expect(reloaded.session?.userID == uid)

        store.signOut()
    }

    @Test("signOut clears state + keychain")
    func signOutClears() {
        KeychainHelper.delete(service: "com.dripadvisor.DripAdvisor", account: "session")
        let store = AuthStore()
        store.signIn(token: "t", userID: UUID(), expiresAt: .now.addingTimeInterval(60))
        store.signOut()
        #expect(store.session == nil)
        let reloaded = AuthStore()
        #expect(reloaded.session == nil)
    }
}

import SwiftUI

@main
struct DripAdvisorApp: App {
    @State private var store = DripStore()
    @State private var auth: AuthStore
    @State private var chat: ChatStore
    private let api: DripAPI
    private let chatAPI: ChatAPI
    private let chatSocket: ChatSocket

    init() {
        let a = AuthStore()
        _auth = State(initialValue: a)
        // Single long-lived APIClient. Its tokenProvider closure reads the
        // current auth.session lazily, so there's no need to rebuild after login.
        let client = APIClient(tokenProvider: a.tokenProvider)
        api = DripAPI(client: client)
        chatAPI = ChatAPI(client: client)
        chatSocket = ChatSocket(baseURL: client.baseURL, token: a.tokenProvider)
        _chat = State(initialValue: ChatStore(api: chatAPI, socket: chatSocket))
    }

    var body: some Scene {
        WindowGroup {
            RootView(api: api)
                .environment(store)
                .environment(auth)
                .environment(chat)
                .environment(\.dripAPI, api)
                .task(id: auth.isAuthenticated) {
                    if auth.isAuthenticated {
                        let sync = WardrobeSync(api: api)
                        store.sync = sync
                        store.tryOn = TryOnService(api: api)
                        if let remote = try? await sync.pullLatest() {
                            store.hydrateWardrobe(from: remote)
                        }
                        if store.profile.avatarData == nil,
                           let bytes = try? await api.fetchAvatar() {
                            store.setAvatar(bytes)
                        }
                        chat.start()
                    } else {
                        store.sync = nil
                        store.tryOn = nil
                        chat.stop()
                    }
                }
        }
    }
}

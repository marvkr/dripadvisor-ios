import SwiftUI

@main
struct DripAdvisorApp: App {
    @State private var store = DripStore()
    @State private var auth: AuthStore
    private let api: DripAPI

    init() {
        let a = AuthStore()
        _auth = State(initialValue: a)
        // Single long-lived APIClient. Its tokenProvider closure reads the
        // current auth.session lazily, so there's no need to rebuild after login.
        api = DripAPI(client: APIClient(tokenProvider: a.tokenProvider))
    }

    var body: some Scene {
        WindowGroup {
            RootView(api: api)
                .environment(store)
                .environment(auth)
                .task(id: auth.isAuthenticated) {
                    if auth.isAuthenticated {
                        let sync = WardrobeSync(api: api)
                        store.sync = sync
                        store.tryOn = TryOnService(api: api)
                        // Hydrate wardrobe from backend — server is the source of truth
                        // for items added on another device.
                        if let remote = try? await sync.pullLatest() {
                            store.hydrateWardrobe(from: remote)
                        }
                    } else {
                        store.sync = nil
                        store.tryOn = nil
                    }
                }
        }
    }
}

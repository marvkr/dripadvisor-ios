import SwiftUI

struct RootView: View {
    let api: DripAPI

    @Environment(DripStore.self) private var store
    @Environment(AuthStore.self) private var auth

    var body: some View {
        Group {
            if !auth.isAuthenticated {
                SignInView(auth: auth, api: api)
                    .transition(.opacity)
            } else if store.isOnboarded {
                MainTabView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                AvatarSetupView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: auth.isAuthenticated)
        .animation(.easeInOut(duration: 0.35), value: store.isOnboarded)
    }
}

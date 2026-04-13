import SwiftUI

struct RootView: View {
    @Environment(DripStore.self) private var store

    var body: some View {
        Group {
            if store.isOnboarded {
                MainTabView()
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else {
                AvatarSetupView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: store.isOnboarded)
    }
}

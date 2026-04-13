import SwiftUI

@main
struct DripAdvisorApp: App {
    @State private var store = DripStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
        }
    }
}

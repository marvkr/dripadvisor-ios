import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .wardrobe
    @State private var entitlements = EntitlementStore()
    @State private var showingPaywall = false

    var body: some View {
        ZStack(alignment: .bottom) {
            switch selectedTab {
            case .wardrobe: WardrobeView()
            case .outfits: OutfitsView()
            case .stylist: ChatListView()
            }

            FloatingTabBar(selectedTab: $selectedTab)
        }
        .overlay(alignment: .topTrailing) {
            if !entitlements.isPro {
                Button(action: { showingPaywall = true }) {
                    Label("Pro", systemImage: "sparkles")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.buttonPrimary, in: Capsule())
                }
                .padding(.top, 6)
                .padding(.trailing, 16)
            }
        }
        .sheet(isPresented: $showingPaywall) {
            PaywallView()
        }
    }
}

import SwiftUI

struct MainTabView: View {
    @State private var selectedTab: AppTab = .wardrobe

    var body: some View {
        ZStack(alignment: .bottom) {
            Group {
                switch selectedTab {
                case .wardrobe: WardrobeView()
                case .outfits: OutfitsView()
                case .stylist: StyleAgentView()
                }
            }

            FloatingTabBar(selectedTab: $selectedTab)
        }
    }
}

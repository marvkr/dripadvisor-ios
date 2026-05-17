import SwiftUI

enum AppTab: Hashable {
    case wardrobe, outfits, stylist
}

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab

    @Namespace private var indicatorNamespace

    var body: some View {
        HStack(spacing: 0) {
            tabButton(tab: .wardrobe) {
                HangerIcon()
                    .fill(selectedTab == .wardrobe ? Theme.iconActive : Theme.iconInactive)
                    .frame(width: 22, height: 22)
            }

            tabButton(tab: .outfits) {
                TShirtIconView(
                    size: 22,
                    color: selectedTab == .outfits ? Theme.iconActive : Theme.iconInactive,
                    lineWidth: 1.5
                )
            }

            tabButton(tab: .stylist) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(selectedTab == .stylist ? Theme.iconActive : Theme.iconInactive)
                    .symbolEffect(.bounce, value: selectedTab == .stylist)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .clipShape(Capsule())
        .overlay(
            Capsule().strokeBorder(
                LinearGradient(
                    colors: [Theme.glassBorder, Theme.glassBorderLight],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1.5
            )
        )
        .shadow(color: .black.opacity(0.1), radius: 12, y: 0)
        .fixedSize()
    }

    private func tabButton<Content: View>(tab: AppTab, @ViewBuilder icon: () -> Content) -> some View {
        Button {
            withAnimation(.spring(duration: 0.4, bounce: 0.35)) { selectedTab = tab }
        } label: {
            icon()
                .frame(width: 44, height: 36)
                .scaleEffect(selectedTab == tab ? 1.12 : 1)
                .background {
                    if selectedTab == tab {
                        Circle()
                            .fill(Color.black.opacity(0.06))
                            .frame(width: 36, height: 36)
                            .matchedGeometryEffect(id: "selectedTabIndicator", in: indicatorNamespace)
                    }
                }
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

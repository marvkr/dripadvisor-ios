import SwiftUI

/// Minimal wardrobe cell: cutout garment on background, no chrome.
/// Whering / Closetspace-style closet density. Metadata lives in the detail
/// sheet, not the grid cell.
struct WardrobeItemCard: View {
    let item: WardrobeItem

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.bg
                if let image = item.uiImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(8)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                } else {
                    Image(systemName: item.category.systemImage)
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(Theme.textDisabled)
                }
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .clipShape(.rect(cornerRadius: 18))
    }
}

import SwiftUI

/// Sticker-style wardrobe cell: cutout garment with white contour + soft
/// shadow, name as a die-cut pill label below.
struct WardrobeItemCard: View {
    let item: WardrobeItem

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Theme.bg
                if let image = item.uiImage {
                    StickerImage(uiImage: image, borderWidth: 6, shadowRadius: 8)
                        .padding(12)
                } else {
                    Image(systemName: item.category.systemImage)
                        .font(.system(size: 36, weight: .ultraLight))
                        .foregroundStyle(Theme.textDisabled)
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 18))

            StickerLabel(text: item.name)
                .lineLimit(1)
                .padding(.bottom, 4)
        }
    }
}

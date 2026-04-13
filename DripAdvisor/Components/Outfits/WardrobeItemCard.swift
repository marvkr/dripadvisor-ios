import SwiftUI

struct WardrobeItemCard: View {
    let item: WardrobeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                Rectangle().fill(Theme.bg)
                if let image = item.uiImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: item.category.systemImage)
                        .font(.system(size: 40, weight: .ultraLight))
                        .foregroundStyle(Theme.textDisabled)
                }
            }
            .aspectRatio(0.75, contentMode: .fit)
            .clipped()

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(item.brand)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
                Text(item.category.displayName.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textDisabled)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .glassCard()
    }
}

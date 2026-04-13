import SwiftUI

struct OutfitRow: View {
    @Environment(DripStore.self) private var store
    let outfit: Outfit

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 2) {
                slotImage(store.item(for: outfit.topID))
                slotImage(store.item(for: outfit.bottomID))
            }
            .aspectRatio(0.75, contentMode: .fit)
            .clipShape(.rect(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 2) {
                Text(outfit.name)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if !outfit.occasion.isEmpty {
                    Text(outfit.occasion)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textMuted)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
        .glassCard()
    }

    private func slotImage(_ item: WardrobeItem?) -> some View {
        ZStack {
            Rectangle().fill(Theme.bg)
            if let item, let image = item.uiImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(Theme.textDisabled)
            }
        }
    }
}

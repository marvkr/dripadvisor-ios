import SwiftUI

/// Full-screen detail for a single wardrobe item. Shows the cutout + every
/// known field + source-specific CTA (Buy URL for wishlist / Mark Worn for
/// owned) + Try-On.
struct WardrobeItemDetailView: View {
    @Environment(DripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let itemID: UUID
    @State private var showTryOn = false

    private var item: WardrobeItem? {
        store.item(for: itemID)
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            if let item {
                ScrollView {
                    VStack(spacing: 20) {
                        WardrobeDetailHero(item: item)
                        WardrobeDetailMeta(item: item)
                        WardrobeDetailFields(item: item)
                        WardrobeDetailActions(
                            item: item,
                            onTryOn: { showTryOn = true },
                            onMarkWorn: { Task { await markWorn(item) } },
                            onDelete: { delete(item) }
                        )
                    }
                    .padding(20)
                    .padding(.bottom, 60)
                }
            } else {
                Text("Item no longer in your wardrobe")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                    .labelStyle(.iconOnly)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .sheet(isPresented: $showTryOn) {
            if let item {
                TryOnView(item: item)
            }
        }
    }

    @MainActor
    private func markWorn(_ item: WardrobeItem) async {
        store.markWorn(itemID: item.id)
    }

    private func delete(_ item: WardrobeItem) {
        store.removeItem(item)
        dismiss()
    }
}

private struct WardrobeDetailHero: View {
    let item: WardrobeItem

    var body: some View {
        ZStack {
            Theme.bg
            if let image = item.uiImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(28)
            } else {
                Image(systemName: item.category.systemImage)
                    .font(.system(size: 60, weight: .ultraLight))
                    .foregroundStyle(Theme.textDisabled)
            }
        }
        .frame(height: 340)
        .frame(maxWidth: .infinity)
        .clipShape(.rect(cornerRadius: 24))
        .overlay(alignment: .topLeading) {
            SourceBadge(source: item.source)
                .padding(12)
        }
    }
}

private struct SourceBadge: View {
    let source: WardrobeItemSource

    var body: some View {
        Label(source.displayName, systemImage: source == .wishlist ? "heart.fill" : "house.fill")
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Theme.buttonPrimary, in: Capsule())
    }
}

private struct WardrobeDetailMeta: View {
    let item: WardrobeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.name)
                .font(.system(size: 26, weight: .bold, design: .serif))
                .foregroundStyle(Theme.textPrimary)
            Text(item.brand)
                .font(.title3)
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 8) {
                Text(item.category.displayName.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textDisabled)
                if let days = item.daysSinceWorn {
                    Text("•")
                        .foregroundStyle(Theme.textDisabled)
                    Text("Worn \(days)d ago")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.textDisabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WardrobeDetailFields: View {
    let item: WardrobeItem

    var rows: [(String, String)] {
        var out: [(String, String)] = []
        if let s = item.size { out.append(("Size", s)) }
        if let c = item.color { out.append(("Color", c)) }
        if let m = item.material { out.append(("Material", m)) }
        if let p = item.retailPrice {
            out.append(("Retail", formatPrice(p, currency: item.currency)))
        }
        if let p = item.pricePaid {
            out.append(("Paid", formatPrice(p, currency: item.currency)))
        }
        if item.wearCount > 0 {
            out.append(("Worn", "\(item.wearCount) times"))
        }
        if !item.tags.isEmpty {
            out.append(("Tags", item.tags.joined(separator: ", ")))
        }
        return out
    }

    var body: some View {
        if !rows.isEmpty {
            VStack(spacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { idx, row in
                    HStack {
                        Text(row.0)
                            .font(.subheadline)
                            .foregroundStyle(Theme.textMuted)
                        Spacer()
                        Text(row.1)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .padding(.vertical, 12)
                    if idx < rows.count - 1 {
                        Divider().background(Theme.glassBorder)
                    }
                }
            }
            .padding(.horizontal, 16)
            .glassCard()
        }
    }
}

private struct WardrobeDetailActions: View {
    let item: WardrobeItem
    let onTryOn: () -> Void
    let onMarkWorn: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Button(action: onTryOn) {
                Label("Try On", systemImage: "sparkles")
                    .primaryButton()
            }

            if item.source == .wishlist, let url = item.sourceURL {
                Link(destination: url) {
                    Label("Open Source", systemImage: "safari")
                        .secondaryButton()
                }
            } else if item.source == .owned {
                Button(action: onMarkWorn) {
                    Label("Mark as Worn", systemImage: "checkmark.circle")
                        .secondaryButton()
                }
            }

            Button(role: .destructive, action: onDelete) {
                Label("Delete", systemImage: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.error)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
        }
    }
}

private func formatPrice(_ value: Double, currency: String?) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = currency ?? "USD"
    return f.string(from: value as NSNumber) ?? String(format: "%.2f", value)
}

import SwiftUI
import PhotosUI

struct WardrobeView: View {
    @Environment(DripStore.self) private var store
    @State private var isAddingItem = false
    @State private var tryOnItem: WardrobeItem?

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    if store.wardrobe.isEmpty {
                        WardrobeEmptyState(onAdd: { isAddingItem = true })
                    } else {
                        wardrobeGrid
                    }
                }

                WardrobeFAB(action: { isAddingItem = true })
            }
            .navigationTitle("Wardrobe")
            .sheet(isPresented: $isAddingItem) {
                AddWardrobeItemView()
            }
            .sheet(item: $tryOnItem, content: TryOnView.init)
        }
    }

    private var wardrobeGrid: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(store.wardrobe) { item in
                Button { tryOnItem = item } label: {
                    WardrobeItemCard(item: item)
                }
                .buttonStyle(WardrobeCardPressStyle())
                .contextMenu {
                    Button("Try On", action: { tryOnItem = item })
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
                            store.removeItem(item)
                        }
                    }
                } preview: {
                    WardrobeItemPreview(item: item)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 100)
        .animation(.spring(duration: 0.45, bounce: 0.3), value: store.wardrobe.count)
    }
}

/// Long-press preview — surfaces the metadata that we removed from the grid
/// cell. Tap-and-hold any wardrobe cutout to see name / brand / category.
struct WardrobeItemPreview: View {
    let item: WardrobeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Theme.bg
                if let image = item.uiImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                }
            }
            .frame(width: 280, height: 280)
            .clipShape(.rect(cornerRadius: 20))

            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                Text(item.brand)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Text(item.category.displayName.uppercased())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Theme.textDisabled)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 12)
        }
        .frame(width: 280)
        .background(.background)
    }
}

struct WardrobeCardPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(duration: 0.25, bounce: 0.4), value: configuration.isPressed)
    }
}

struct WardrobeEmptyState: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 80)
            HangerIconView(size: 60, color: Theme.textMuted)
            Text("Your wardrobe is empty")
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(Theme.textPrimary)
            Text("Tap + to screenshot or upload clothing.\nThe AI extracts each garment so you can try it on.")
                .font(.subheadline)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}

struct WardrobeFAB: View {
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.system(size: 28))
                .foregroundStyle(Theme.textSecondary)
                .symbolEffect(.bounce, value: pulse)
                .frame(width: 56, height: 56)
                .background(.ultraThinMaterial)
                .clipShape(.rect(cornerRadius: 28))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(Theme.glassBorder, lineWidth: 1.5)
                )
                .shadow(color: .black.opacity(0.1), radius: 8, y: 0)
        }
        .buttonStyle(WardrobeCardPressStyle())
        .simultaneousGesture(TapGesture().onEnded { pulse.toggle() })
        .padding(.trailing, 20)
        .padding(.bottom, 60)
    }
}

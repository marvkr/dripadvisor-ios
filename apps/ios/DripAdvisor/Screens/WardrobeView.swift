import SwiftUI
import PhotosUI

enum WardrobeFilter: Hashable {
    case all
    case closet
    case wishlist
}

struct WardrobeView: View {
    @Environment(DripStore.self) private var store
    @State private var addAction: AddAction?
    @State private var detailItemID: UUID?
    @State private var filter: WardrobeFilter = .all

    enum AddAction: Identifiable, Hashable {
        case fromCloset
        case fromWeb
        var id: Int { hashValue }
    }

    private var filtered: [WardrobeItem] {
        switch filter {
        case .all: store.wardrobe
        case .closet: store.wardrobe.filter { $0.source == .owned }
        case .wishlist: store.wardrobe.filter { $0.source == .wishlist }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Theme.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    WardrobeFilterBar(filter: $filter)

                    if filtered.isEmpty {
                        ScrollView {
                            WardrobeEmptyState(onAdd: { addAction = .fromCloset })
                        }
                    } else {
                        ScrollView {
                            wardrobeGrid
                        }
                    }
                }

                WardrobeFAB(onCloset: { addAction = .fromCloset },
                            onWeb:    { addAction = .fromWeb })
            }
            .navigationTitle("Wardrobe")
            .sheet(item: $addAction) { action in
                switch action {
                case .fromCloset: AddWardrobeItemView()
                case .fromWeb:    AddFromWebView()
                }
            }
            .sheet(item: Binding(
                get: { detailItemID.map(IDWrapper.init(value:)) },
                set: { detailItemID = $0?.value }
            )) { wrap in
                WardrobeItemDetailView(itemID: wrap.value)
            }
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
            ForEach(filtered) { item in
                Button { detailItemID = item.id } label: {
                    WardrobeItemCard(item: item)
                }
                .buttonStyle(WardrobeCardPressStyle())
                .contextMenu {
                    Button("Try On", systemImage: "sparkles") {
                        detailItemID = item.id
                    }
                    if item.source == .owned {
                        Button("Mark as Worn", systemImage: "checkmark.circle") {
                            store.markWorn(itemID: item.id)
                        }
                    }
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
        .animation(.spring(duration: 0.45, bounce: 0.3), value: filtered.count)
    }
}

// MARK: - Filter bar

struct WardrobeFilterBar: View {
    @Binding var filter: WardrobeFilter

    var body: some View {
        HStack(spacing: 6) {
            chip(.all, "All")
            chip(.closet, "Closet")
            chip(.wishlist, "Wishlist")
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func chip(_ f: WardrobeFilter, _ label: String) -> some View {
        Button {
            withAnimation(.spring(duration: 0.25, bounce: 0.3)) { filter = f }
        } label: {
            Text(label)
                .font(.footnote.weight(.medium))
                .foregroundStyle(filter == f ? .white : Theme.textSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background {
                    if filter == f {
                        Capsule().fill(Theme.buttonPrimary)
                    } else {
                        Capsule().fill(Color.white.opacity(0.6))
                    }
                }
                .overlay(Capsule().strokeBorder(filter == f ? .clear : Theme.glassBorder, lineWidth: 1))
        }
        .buttonStyle(.plain)
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
    let onCloset: () -> Void
    let onWeb: () -> Void
    @State private var pulse = false

    var body: some View {
        Menu {
            Button("From closet", systemImage: "camera") { pulse.toggle(); onCloset() }
            Button("From web", systemImage: "link") { pulse.toggle(); onWeb() }
        } label: {
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
        .padding(.trailing, 20)
        .padding(.bottom, 60)
    }
}

/// Long-press preview surfaces the metadata removed from the grid cell.
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

/// Bridge type so a sheet can bind to an optional UUID via Identifiable.
struct IDWrapper: Identifiable, Hashable {
    let value: UUID
    var id: UUID { value }
}

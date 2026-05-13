import SwiftUI

struct OutfitBuilderView: View {
    @Environment(DripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var topID: UUID?
    @State private var bottomID: UUID?
    @State private var shoesID: UUID?
    @State private var name = ""
    @State private var occasion = ""

    private var canSave: Bool {
        !name.isEmpty && (topID != nil || bottomID != nil || shoesID != nil)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        ItemSlotSection(title: "Select a Top", category: .top, selection: $topID)
                        ItemSlotSection(title: "Select a Bottom", category: .bottom, selection: $bottomID)
                        ItemSlotSection(title: "Select Shoes", category: .shoes, selection: $shoesID)
                        VStack(spacing: 12) {
                            FocusableInput(placeholder: "Outfit name", text: $name)
                            FocusableInput(placeholder: "Occasion — e.g. Date night", text: $occasion)
                        }
                        Button(action: save) {
                            Text("Save Outfit").primaryButton()
                        }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.4)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Build Outfit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
    }

    private func save() {
        store.saveOutfit(Outfit(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            occasion: occasion.trimmingCharacters(in: .whitespacesAndNewlines),
            topID: topID,
            bottomID: bottomID,
            shoesID: shoesID
        ))
        dismiss()
    }
}

struct ItemSlotSection: View {
    @Environment(DripStore.self) private var store
    let title: String
    let category: GarmentCategory
    @Binding var selection: UUID?

    var body: some View {
        let items = store.items(in: category)
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(Theme.textPrimary)

            if items.isEmpty {
                Text("No items yet.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textMuted)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassCard()
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(items) { item in
                            Button {
                                selection = selection == item.id ? nil : item.id
                            } label: {
                                ItemSlotChip(item: item, isSelected: selection == item.id)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct ItemSlotChip: View {
    let item: WardrobeItem
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                if let image = item.uiImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: item.category.systemImage)
                        .foregroundStyle(Theme.textDisabled)
                }
            }
            .frame(width: 80, height: 68)
            .background(Theme.bg)
            .clipShape(.rect(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(isSelected ? Theme.iconActive : .clear, lineWidth: 2)
            )

            Text(item.name)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
                .frame(width: 80)
        }
    }
}

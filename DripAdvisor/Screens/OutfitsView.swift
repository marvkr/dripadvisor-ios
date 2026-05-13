import SwiftUI

struct OutfitsView: View {
    @Environment(DripStore.self) private var store
    @State private var isBuilding = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    if store.outfits.isEmpty {
                        OutfitsEmptyState(onBuild: { isBuilding = true })
                    } else {
                        LazyVGrid(columns: [
                            GridItem(.flexible(), spacing: 6),
                            GridItem(.flexible(), spacing: 6)
                        ], spacing: 6) {
                            ForEach(store.outfits) { outfit in
                                OutfitRow(outfit: outfit)
                                    .contextMenu {
                                        Button("Delete", systemImage: "trash", role: .destructive, action: { store.removeOutfit(outfit) })
                                    }
                            }
                        }
                        .padding(8)
                        .padding(.bottom, 100)
                    }
                }

                WardrobeFAB(onCloset: { isBuilding = true }, onWeb: { isBuilding = true })
            }
            .navigationTitle("Outfits")
            .sheet(isPresented: $isBuilding) {
                OutfitBuilderView()
            }
        }
    }
}

struct OutfitsEmptyState: View {
    let onBuild: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 80)
            HangerIconView(size: 60, color: Theme.textMuted)
            Text("No outfits yet")
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(Theme.textPrimary)
            Text("Build a look by mixing a top and bottom from your wardrobe.")
                .font(.subheadline)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
            Button(action: onBuild) {
                Label("Pick Manually", systemImage: "hand.tap")
                    .primaryButton()
            }
            Spacer()
        }
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity)
    }
}

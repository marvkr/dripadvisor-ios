import SwiftUI

struct ProfileView: View {
    @Environment(DripStore.self) private var store
    @Environment(AuthStore.self) private var auth

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 24) {
                        ProfileAvatar(profile: store.profile)
                        ProfileStats(
                            items: store.wardrobe.count,
                            outfits: store.outfits.count,
                            chats: store.messages.count(where: { $0.role == .stylist })
                        )
                        Button(role: .destructive, action: { withAnimation { store.clearAvatar() } }) {
                            Label("Reset Avatar", systemImage: "arrow.counterclockwise")
                                .secondaryButton()
                        }
                        if auth.isAuthenticated {
                            Button(role: .destructive, action: { auth.signOut() }) {
                                Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                                    .secondaryButton()
                            }
                        }
                    }
                    .padding(24)
                }
            }
            .navigationTitle("Profile")
        }
    }
}

struct ProfileAvatar: View {
    let profile: UserProfile

    var body: some View {
        VStack(spacing: 16) {
            Group {
                if let image = profile.avatarUIImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(Theme.textDisabled)
                }
            }
            .frame(width: 160, height: 160)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(Theme.glassBorder, lineWidth: 1.5))

            Text(profile.displayName)
                .font(.system(size: 20, weight: .bold, design: .serif))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

struct ProfileStats: View {
    let items: Int
    let outfits: Int
    let chats: Int

    var body: some View {
        HStack(spacing: 12) {
            statCard(value: items, label: "Items")
            statCard(value: outfits, label: "Outfits")
            statCard(value: chats, label: "Chats")
        }
    }

    private func statCard(value: Int, label: String) -> some View {
        VStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundStyle(Theme.textPrimary)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .glassCard()
    }
}

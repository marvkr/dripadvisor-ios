import SwiftUI

/// Top-level list of conversations. iMessage-style: row per chat with name,
/// preview, time, unread dot.
struct ChatListView: View {
    @Environment(ChatStore.self) private var store
    @State private var selectedID: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if store.conversations.isEmpty && store.loading {
                    ProgressView()
                } else if store.conversations.isEmpty {
                    emptyState
                } else {
                    List(store.conversations, selection: $selectedID) { c in
                        NavigationLink(value: c.id) {
                            ConversationRow(conversation: c)
                        }
                        .listRowBackground(Theme.bg)
                        .listRowSeparator(.hidden)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Chats")
            .navigationDestination(for: UUID.self) { id in
                ChatThreadView(chatID: id)
            }
            .refreshable { await store.refreshConversations() }
        }
        .task { store.start() }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "message")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Theme.textDisabled)
            Text("No conversations yet")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.textPrimary)
            Text("Start a chat from your friends list or talk to the stylist.")
                .font(.subheadline)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }
}

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            avatar
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(conversation.displayTitle)
                        .font(.system(size: 16, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    if let when = conversation.lastMessageAt {
                        Text(when.formatted(.relative(presentation: .numeric)))
                            .font(.caption)
                            .foregroundStyle(Theme.textMuted)
                    }
                }
                Text(conversation.lastMessagePreview ?? "—")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Image(systemName: conversation.type == .direct ? "person" : "person.2")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(width: 44, height: 44)
        .overlay(Circle().strokeBorder(Theme.glassBorder, lineWidth: 1))
    }
}

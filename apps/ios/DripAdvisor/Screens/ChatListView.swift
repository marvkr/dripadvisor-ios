import SwiftUI

/// Top-level list of conversations. iMessage-style: row per chat with name,
/// preview, time, unread dot.
struct ChatListView: View {
    @Environment(ChatStore.self) private var store
    @State private var path: [UUID] = []
    @State private var creating = false
    @State private var lastError: String?

    var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                Theme.bg.ignoresSafeArea()
                if store.conversations.isEmpty && store.loading {
                    ProgressView()
                } else if store.conversations.isEmpty {
                    emptyState
                } else {
                    List(store.conversations) { c in
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: openStylist) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .disabled(creating)
                }
            }
            .alert("Couldn't open chat", isPresented: .init(
                get: { lastError != nil },
                set: { if !$0 { lastError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(lastError ?? "")
            }
            .refreshable { await store.refreshConversations() }
        }
        .task { store.start() }
    }

    private func openStylist() {
        guard !creating else { return }
        creating = true
        Task {
            if let id = await store.openOrCreateStylistChat() {
                path.append(id)
            } else {
                lastError = store.error ?? "Backend did not return a chat. Check connection."
            }
            creating = false
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "sparkles")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Theme.textDisabled)
            Text("No conversations yet")
                .font(.system(size: 18, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.textPrimary)
            Text("Start a 1:1 with the AI stylist to get outfit suggestions.")
                .font(.subheadline)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(action: openStylist) {
                Label(creating ? "Opening…" : "Talk to Stylist", systemImage: "wand.and.stars")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Theme.buttonPrimary, in: Capsule())
            }
            .disabled(creating)
            .padding(.top, 4)
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

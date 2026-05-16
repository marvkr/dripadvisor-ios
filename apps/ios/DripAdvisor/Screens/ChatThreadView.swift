import SwiftUI

/// Thread view: scrollable bubble list + bottom composer. Auto-scrolls to
/// bottom on new messages via `defaultScrollAnchor(.bottom)`.
struct ChatThreadView: View {
    let chatID: UUID

    @Environment(ChatStore.self) private var store
    @Environment(AuthStore.self) private var auth
    @State private var draft: String = ""
    @FocusState private var composerFocused: Bool

    private var messages: [ConversationMessage] {
        store.messagesByChat[chatID] ?? []
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(messages) { msg in
                        ChatBubble(message: msg, currentUserID: auth.session?.userID)
                            .id(msg.id)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .animation(.spring(duration: 0.35, bounce: 0.25), value: messages.count)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .bottom) {
            ConversationComposer(
                draft: $draft,
                focused: $composerFocused,
                onSend: send
            )
        }
        .navigationBarTitleDisplayMode(.inline)
        .task(id: chatID) { await store.loadMessages(for: chatID) }
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await store.send(text, to: chatID) }
    }
}

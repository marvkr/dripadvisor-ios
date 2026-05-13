import SwiftUI

struct StyleAgentView: View {
    @Environment(DripStore.self) private var store
    @State private var draft = ""
    @FocusState private var isComposerFocused: Bool

    private let suggestionPrompts = [
        "Rooftop dinner tonight",
        "Date night, casual-cool",
        "Office but make it fun",
        "Weekend brunch vibe"
    ]

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                VStack(spacing: 0) {
                    messageList
                    ChatComposer(
                        draft: $draft,
                        isComposerFocused: $isComposerFocused,
                        showSuggestions: store.messages.count <= 1,
                        suggestionPrompts: suggestionPrompts,
                        isSending: store.isStylistThinking,
                        onSend: send
                    )
                }
            }
            .navigationTitle("Stylist")
        }
    }

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                messageListContent
                    .padding(16)
                    .padding(.bottom, 8)
            }
            .onChange(of: store.messages.count) { _, _ in
                withAnimation(.spring(duration: 0.45, bounce: 0.25)) {
                    proxy.scrollTo(store.messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: store.messages.last?.text) { _, _ in
                withAnimation(.easeOut) {
                    proxy.scrollTo(store.messages.last?.id, anchor: .bottom)
                }
            }
        }
    }

    private var messageListContent: some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            ForEach(store.messages) { message in
                bubble(for: message)
            }
            if shouldShowTypingIndicator {
                StylistTypingIndicator()
                    .id("typing")
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.spring(duration: 0.45, bounce: 0.3), value: store.messages.map(\.id))
        .animation(.easeInOut(duration: 0.2), value: store.isStylistThinking)
    }

    private var shouldShowTypingIndicator: Bool {
        store.isStylistThinking && (store.messages.last?.text.isEmpty ?? true)
    }

    private func bubble(for message: ChatMessage) -> some View {
        let streaming = message.id == store.messages.last?.id && store.isStylistThinking
        return MessageBubble(message: message)
            .environment(\.dripIsLatestStreaming, streaming)
            .id(message.id)
    }

    private func send() {
        let text = draft
        draft = ""
        store.sendUserMessage(text)
        isComposerFocused = false
    }
}

struct ChatComposer: View {
    @Binding var draft: String
    var isComposerFocused: FocusState<Bool>.Binding
    let showSuggestions: Bool
    let suggestionPrompts: [String]
    let isSending: Bool
    let onSend: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if showSuggestions {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(suggestionPrompts, id: \.self) { prompt in
                            Button {
                                draft = prompt
                                onSend()
                            } label: {
                                Text(prompt)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(Theme.textSecondary)
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Theme.glassBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 10) {
                composerTextField

                Button("Send", systemImage: "arrow.up", action: onSend)
                    .labelStyle(.iconOnly)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.buttonPrimary, in: Circle())
                    .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty || isSending)
                    .opacity(draft.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 60)
            .padding(.top, 6)
        }
    }

    @ViewBuilder
    private var composerTextField: some View {
        let base = TextField("What should I wear tonight?", text: $draft, axis: .vertical)
            .lineLimit(1...4)
            .focused(isComposerFocused)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .tint(Theme.textPrimary)
            .onSubmit(onSend)
            .animation(.spring(duration: 0.25), value: isComposerFocused.wrappedValue)

        if #available(iOS 26.0, *) {
            base
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 20))
                .overlay(composerBorder)
        } else {
            base
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(composerBorder)
        }
    }

    private var composerBorder: some View {
        RoundedRectangle(cornerRadius: 20)
            .strokeBorder(
                isComposerFocused.wrappedValue ? Color.black.opacity(0.2) : Theme.glassBorder,
                lineWidth: 1.5
            )
    }
}

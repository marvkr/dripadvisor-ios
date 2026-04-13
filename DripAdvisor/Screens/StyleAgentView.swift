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
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(store.messages) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    if store.isStylistThinking {
                        StylistTypingIndicator()
                            .id("typing")
                    }
                }
                .padding(16)
                .padding(.bottom, 8)
            }
            .onChange(of: store.messages.count) { _, _ in
                withAnimation(.easeOut) {
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
                TextField("What should I wear tonight?", text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused(isComposerFocused)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.white.opacity(isComposerFocused.wrappedValue ? 0.85 : 0.55))
                    .clipShape(.rect(cornerRadius: 20))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(
                                isComposerFocused.wrappedValue ? Color.black.opacity(0.2) : Theme.glassBorder,
                                lineWidth: 1.5
                            )
                    )
                    .shadow(
                        color: .black.opacity(isComposerFocused.wrappedValue ? 0.1 : 0.04),
                        radius: isComposerFocused.wrappedValue ? 6 : 1, y: 0
                    )
                    .tint(Theme.textPrimary)
                    .onSubmit(onSend)
                    .animation(.spring(duration: 0.25), value: isComposerFocused.wrappedValue)

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
}

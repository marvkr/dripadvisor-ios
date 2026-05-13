import SwiftUI

struct MessageBubble: View {
    @Environment(DripStore.self) private var store
    @Environment(\.dripIsLatestStreaming) private var isLatestStreaming
    let message: ChatMessage

    private var showCursor: Bool {
        message.role == .stylist && isLatestStreaming
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.role == .stylist {
                bubbleContent
                Spacer(minLength: 48)
            } else {
                Spacer(minLength: 48)
                bubbleContent
            }
        }
        .transition(
            .asymmetric(
                insertion: .move(edge: message.role == .user ? .trailing : .leading)
                    .combined(with: .opacity)
                    .combined(with: .scale(scale: 0.94)),
                removal: .opacity
            )
        )
    }

    private var bubbleContent: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 10) {
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(message.text.isEmpty ? " " : message.text)
                    .font(.system(size: 15))
                    .foregroundStyle(message.role == .user ? .white : Theme.textSecondary)
                if showCursor {
                    BlinkingCursor()
                }
            }
            .padding(12)
            .background {
                if message.role == .user {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Theme.buttonPrimary)
                } else {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color.white.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20)
                                .strokeBorder(Theme.glassBorder, lineWidth: 1.5)
                        )
                }
            }

            if !message.suggestedItemIDs.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(message.suggestedItemIDs.enumerated()), id: \.element) { index, id in
                            if let item = store.item(for: id) {
                                SuggestedItemCard(item: item)
                                    .transition(
                                        .scale(scale: 0.8)
                                        .combined(with: .opacity)
                                    )
                                    .animation(
                                        .spring(duration: 0.55, bounce: 0.45).delay(Double(index) * 0.08),
                                        value: message.suggestedItemIDs
                                    )
                            }
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct BlinkingCursor: View {
    @State private var on = true

    var body: some View {
        Rectangle()
            .fill(Theme.textSecondary)
            .frame(width: 2, height: 14)
            .opacity(on ? 1 : 0)
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .milliseconds(500))
                    on.toggle()
                }
            }
    }
}

private struct DripIsLatestStreamingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var dripIsLatestStreaming: Bool {
        get { self[DripIsLatestStreamingKey.self] }
        set { self[DripIsLatestStreamingKey.self] = newValue }
    }
}

struct SuggestedItemCard: View {
    let item: WardrobeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                Rectangle().fill(Theme.bg)
                if let image = item.uiImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: item.category.systemImage)
                        .font(.title3)
                        .foregroundStyle(Theme.textDisabled)
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.glassBorder, lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(item.name)
                    .font(.system(size: 13, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(item.brand)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.textMuted)
                    .lineLimit(1)
            }
            .frame(width: 120, alignment: .leading)
        }
    }
}

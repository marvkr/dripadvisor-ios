import SwiftUI

/// One message bubble. iMessage-style: outgoing = dark right, incoming =
/// light left, agent = special tint w/ sparkles glyph.
struct ChatBubble: View {
    let message: ConversationMessage
    let currentUserID: UUID?

    private var isMine: Bool {
        guard let uid = currentUserID, let sender = message.senderUserID else { return false }
        return uid == sender
    }

    private var alignment: HorizontalAlignment {
        isMine ? .trailing : .leading
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isMine { Spacer(minLength: 48) }
            VStack(alignment: alignment, spacing: 4) {
                if message.isAgent && !isMine {
                    Label("Stylist", systemImage: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.textMuted)
                        .padding(.leading, 4)
                }
                bubble
            }
            if !isMine { Spacer(minLength: 48) }
        }
    }

    @ViewBuilder
    private var bubble: some View {
        let text = message.isDeleted
            ? "Message deleted"
            : (message.body ?? "[unsupported message]")
        let italics = message.isDeleted
        Text(text)
            .italic(italics)
            .font(.system(size: 15))
            .foregroundStyle(isMine ? Color.white : Theme.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(isMine ? Theme.buttonPrimary : Color.white.opacity(0.7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .strokeBorder(isMine ? .clear : Theme.glassBorder, lineWidth: 1)
                    )
            )
    }
}

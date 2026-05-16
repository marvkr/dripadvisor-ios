import SwiftUI

/// Bottom-sticky input bar. Multiline text field with rounded glass border
/// and a send button that activates when the draft has content.
struct ConversationComposer: View {
    @Binding var draft: String
    var focused: FocusState<Bool>.Binding
    let onSend: () -> Void

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $draft, axis: .vertical)
                .focused(focused)
                .lineLimit(1...5)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(focused.wrappedValue ? Color.black.opacity(0.18) : Theme.glassBorder, lineWidth: 1.2)
                )
                .tint(Theme.textPrimary)
                .onSubmit(onSend)
                .animation(.spring(duration: 0.2), value: focused.wrappedValue)

            Button(action: onSend) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Theme.buttonPrimary, in: Circle())
            }
            .disabled(!canSend)
            .opacity(canSend ? 1 : 0.4)
            .scaleEffect(canSend ? 1 : 0.92)
            .animation(.spring(duration: 0.25, bounce: 0.35), value: canSend)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(
            Divider().background(Theme.glassBorder),
            alignment: .top
        )
    }
}

import SwiftUI
import PhotosUI

struct AvatarSetupView: View {
    @Environment(DripStore.self) private var store
    @State private var pickerItem: PhotosPickerItem?
    @State private var previewImage: UIImage?
    @State private var isLoading = false

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()
                AvatarHeader()
                AvatarPreview(previewImage: previewImage, isLoading: isLoading)
                AvatarTips()
                Spacer()
                avatarActions
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
        .task(id: pickerItem) {
            await loadImage()
        }
    }

    private var avatarActions: some View {
        VStack(spacing: 12) {
            PhotosPicker(selection: $pickerItem, matching: .images, photoLibrary: .shared()) {
                Label(previewImage == nil ? "Upload Photo" : "Change Photo", systemImage: "photo.on.rectangle")
                    .primaryButton()
            }
            .disabled(isLoading)

            if previewImage != nil {
                Button(action: commit) {
                    Label("Continue", systemImage: "arrow.right")
                        .secondaryButton()
                }
            }
        }
    }

    @MainActor
    private func loadImage() async {
        guard let pickerItem else { return }
        isLoading = true
        defer { isLoading = false }
        if let data = try? await pickerItem.loadTransferable(type: Data.self),
           let image = UIImage(data: data) {
            previewImage = image
        }
    }

    private func commit() {
        guard let previewImage, let data = previewImage.jpegData(compressionQuality: 0.85) else { return }
        withAnimation { store.setAvatar(data) }
    }
}

// MARK: - Extracted subviews

struct AvatarHeader: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("DripAdvisor")
                .font(.system(size: 36, weight: .bold, design: .serif))
                .foregroundStyle(Theme.textPrimary)

            Text("You are the model.")
                .font(.system(size: 16, design: .serif))
                .foregroundStyle(Theme.textMuted)

            Text("Take or upload a full-body photo.\nThis becomes your avatar for every try-on.")
                .font(.subheadline)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
        }
    }
}

struct AvatarPreview: View {
    let previewImage: UIImage?
    let isLoading: Bool

    var body: some View {
        ZStack {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(.rect(cornerRadius: 24))
            } else {
                VStack(spacing: 16) {
                    UserPositionIcon(size: 80, color: Theme.textDisabled)
                    Text("Full-body photo")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textMuted)
                }
            }

            if isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                    ProgressView().tint(.white)
                }
                .clipShape(.rect(cornerRadius: 24))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 260)
        .glassCard()
    }
}

struct AvatarTips: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            tipRow(icon: "sun.max.fill", text: "Good lighting, neutral background")
            tipRow(icon: "camera.fill", text: "Full body, facing camera")
            tipRow(icon: "hand.raised.fill", text: "Arms slightly away from body")
        }
        .padding(20)
        .glassCard()
    }

    private func tipRow(icon: String, text: String) -> some View {
        Label(text, systemImage: icon)
            .font(.subheadline)
            .foregroundStyle(Theme.textBody)
            .labelStyle(TipLabelStyle())
    }
}

private struct TipLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 12) {
            configuration.icon
                .foregroundStyle(Theme.textMuted)
                .frame(width: 24)
            configuration.title
            Spacer()
        }
    }
}

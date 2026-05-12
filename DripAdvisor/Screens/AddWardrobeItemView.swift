import SwiftUI
import PhotosUI

struct AddWardrobeItemView: View {
    @Environment(DripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var pickerItem: PhotosPickerItem?
    @State private var imageData: Data?
    @State private var previewImage: UIImage?
    @State private var name = ""
    @State private var brand = ""
    @State private var category: GarmentCategory = .top
    @State private var isExtracting = false
    @State private var hasExtracted = false

    private var canSave: Bool {
        imageData != nil && !name.isEmpty && !brand.isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 20) {
                        AddItemPhotoSection(
                            previewImage: previewImage,
                            hasExtracted: hasExtracted,
                            isExtracting: isExtracting,
                            pickerItem: $pickerItem
                        )
                        AddItemFormSection(name: $name, brand: $brand, category: $category)
                        Button(action: save) {
                            Text("Add to Wardrobe")
                                .primaryButton()
                        }
                        .disabled(!canSave)
                        .opacity(canSave ? 1 : 0.4)
                        .scaleEffect(canSave ? 1 : 0.98)
                        .animation(.spring(duration: 0.35, bounce: 0.3), value: canSave)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("New Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close", systemImage: "xmark", action: dismiss.callAsFunction)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .task(id: pickerItem) {
                await loadImage()
            }
        }
    }

    @MainActor
    private func loadImage() async {
        guard let pickerItem else { return }
        isExtracting = true
        defer { isExtracting = false }
        guard
            let rawData = try? await pickerItem.loadTransferable(type: Data.self),
            let rawImage = UIImage(data: rawData)
        else { return }

        let extracted = await Task.detached(priority: .userInitiated) {
            try? await BackgroundRemover.removeBackground(from: rawImage)
        }.value

        if let extracted, let extractedImage = UIImage(data: extracted) {
            imageData = extracted
            previewImage = extractedImage
            hasExtracted = true
        } else {
            imageData = rawData
            previewImage = rawImage
            hasExtracted = false
        }
    }

    private func save() {
        guard let imageData else { return }
        store.addItem(WardrobeItem(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            brand: brand.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            imageData: imageData
        ))
        dismiss()
    }
}

// MARK: - Subviews

struct AddItemPhotoSection: View {
    let previewImage: UIImage?
    let hasExtracted: Bool
    let isExtracting: Bool
    @Binding var pickerItem: PhotosPickerItem?

    var body: some View {
        ZStack {
            if let previewImage {
                Image(uiImage: previewImage)
                    .resizable()
                    .scaledToFit()
                    .clipShape(.rect(cornerRadius: 20))
                    .id(previewImage.hashValue)
                    .transition(
                        .scale(scale: 0.88)
                        .combined(with: .opacity)
                    )
                    .overlay(alignment: .topTrailing) {
                        if hasExtracted {
                            Label("Extracted", systemImage: "checkmark.seal.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(Theme.buttonPrimary, in: Capsule())
                                .padding(12)
                                .transition(
                                    .scale(scale: 0.6)
                                    .combined(with: .opacity)
                                )
                                .symbolEffect(.bounce, value: hasExtracted)
                        }
                    }
            } else {
                VStack(spacing: 14) {
                    Image(systemName: "photo.stack.fill")
                        .font(.system(size: 48, weight: .ultraLight))
                        .foregroundStyle(Theme.textDisabled)
                        .symbolEffect(.pulse, options: .repeating)
                    Text("Screenshot or photo")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(Theme.textMuted)
                }
                .transition(.opacity)
            }

            if isExtracting {
                ExtractionOverlay()
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.55, bounce: 0.4), value: previewImage)
        .animation(.spring(duration: 0.45, bounce: 0.3), value: hasExtracted)
        .animation(.easeInOut(duration: 0.25), value: isExtracting)
        .frame(height: 300)
        .frame(maxWidth: .infinity)
        .glassCard()
        .overlay(alignment: .bottom) {
            PhotosPicker(selection: $pickerItem, matching: .images) {
                Label(previewImage == nil ? "Choose Photo" : "Replace", systemImage: "photo")
                    .font(.footnote.bold())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.buttonPrimary, in: Capsule())
                    .padding(14)
            }
        }
    }
}

private struct ExtractionOverlay: View {
    @State private var rotate = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
            VStack(spacing: 12) {
                Image(systemName: "scissors")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .rotationEffect(.degrees(rotate ? 12 : -12))
                    .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: rotate)
                Text("Extracting garment…")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white)
            }
        }
        .clipShape(.rect(cornerRadius: 24))
        .onAppear { rotate = true }
    }
}

struct AddItemFormSection: View {
    @Binding var name: String
    @Binding var brand: String
    @Binding var category: GarmentCategory

    var body: some View {
        VStack(spacing: 12) {
            FocusableInput(placeholder: "Name — e.g. Oversized Hoodie", text: $name)
            FocusableInput(placeholder: "Brand — e.g. Lululemon", text: $brand)

            VStack(alignment: .leading, spacing: 8) {
                Text("Category")
                    .font(.system(size: 16, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(GarmentCategory.allCases) { cat in
                            Button { category = cat } label: {
                                Label(cat.displayName, systemImage: cat.systemImage)
                                    .font(.footnote.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .foregroundStyle(category == cat ? .white : Theme.textSecondary)
                                    .background {
                                        if category == cat {
                                            Capsule().fill(Theme.buttonPrimary)
                                        }
                                    }
                                    .background(.ultraThinMaterial, in: Capsule())
                                    .overlay(Capsule().strokeBorder(category == cat ? .clear : Theme.glassBorder, lineWidth: 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }
        }
        .padding(20)
        .glassCard()
    }
}

struct FocusableInput: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        TextField(placeholder, text: $text)
            .textInputAutocapitalization(.words)
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.textPrimary)
            .padding(16)
            .background(Color.white.opacity(0.6))
            .clipShape(.rect(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Theme.glassBorder, lineWidth: 1.5)
            )
            .tint(Theme.textPrimary)
    }
}

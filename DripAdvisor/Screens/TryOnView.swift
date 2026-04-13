import SwiftUI

struct TryOnView: View {
    @Environment(DripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let item: WardrobeItem
    @State private var isGenerating = false
    @State private var generationPhase: GenerationPhase = .idle

    enum GenerationPhase: CaseIterable {
        case idle, analyzing, rendering, composing, done
        var text: String {
            switch self {
            case .idle: "Tap Generate to see it on you"
            case .analyzing: "Analyzing garment…"
            case .rendering: "Rendering avatar…"
            case .composing: "Compositing try-on…"
            case .done: "Ready"
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                TryOnHeader(itemName: item.name, onDismiss: dismiss.callAsFunction)
                TryOnCanvas(item: item, isGenerating: isGenerating, phase: generationPhase)
                TryOnItemInfo(item: item)
                Button(action: { Task { await generate() } }) {
                    Label(
                        store.item(for: item.id)?.tryOnImageData == nil ? "Generate Try-On" : "Regenerate",
                        systemImage: "sparkles"
                    )
                    .primaryButton()
                }
                .disabled(isGenerating)
                .opacity(isGenerating ? 0.4 : 1)
            }
            .padding(24)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @MainActor
    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        for phase in [GenerationPhase.analyzing, .rendering, .composing] {
            generationPhase = phase
            try? await Task.sleep(for: .milliseconds(600))
        }
        await store.simulateTryOn(for: item.id)
        generationPhase = .done
    }
}

struct TryOnHeader: View {
    let itemName: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Virtual Try-On")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Theme.textMuted)
                Text(itemName)
                    .font(.system(size: 20, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            Button("Close", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 36, height: 36)
                .background(.ultraThinMaterial)
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(Theme.glassBorder, lineWidth: 1))
        }
    }
}

struct TryOnCanvas: View {
    @Environment(DripStore.self) private var store
    let item: WardrobeItem
    let isGenerating: Bool
    let phase: TryOnView.GenerationPhase

    var body: some View {
        ZStack {
            if let latest = store.item(for: item.id), let tryOnImage = latest.tryOnUIImage {
                Image(uiImage: tryOnImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(.rect(cornerRadius: 22))
            } else if let avatarImage = store.profile.avatarUIImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(.rect(cornerRadius: 22))
                    .opacity(isGenerating ? 0.5 : 0.8)
                    .overlay {
                        if !isGenerating {
                            VStack(spacing: 8) {
                                Image(systemName: "wand.and.stars")
                                    .font(.system(size: 48, weight: .ultraLight))
                                    .foregroundStyle(Theme.textMuted)
                                Text("Tap Generate")
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
            }

            if isGenerating {
                VStack(spacing: 12) {
                    ProgressView().tint(Theme.textSecondary)
                    Text(phase.text)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                        .contentTransition(.interpolate)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(.ultraThinMaterial, in: Capsule())
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }
}

struct TryOnItemInfo: View {
    let item: WardrobeItem

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if let image = item.uiImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipShape(.rect(cornerRadius: 12))
                } else {
                    Image(systemName: item.category.systemImage)
                        .foregroundStyle(Theme.textDisabled)
                }
            }
            .frame(width: 48, height: 48)
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 15, design: .serif))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(item.brand)
                    .font(.caption)
                    .foregroundStyle(Theme.textMuted)
            }
            Spacer()
            Text(item.category.displayName.uppercased())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textDisabled)
        }
        .padding(14)
        .glassCard()
    }
}

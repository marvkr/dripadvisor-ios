import SwiftUI

struct TryOnView: View {
    @Environment(DripStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    let item: WardrobeItem
    @State private var isGenerating = false
    @State private var generationPhase: GenerationPhase = .idle
    @State private var revealResult = false
    @Namespace private var heroNamespace

    enum GenerationPhase: Int, CaseIterable {
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
        var symbol: String {
            switch self {
            case .idle: "wand.and.stars"
            case .analyzing: "eye"
            case .rendering: "figure.stand"
            case .composing: "rectangle.stack"
            case .done: "checkmark.seal.fill"
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()
            VStack(spacing: 20) {
                TryOnHeader(itemName: item.name, onDismiss: dismiss.callAsFunction)
                TryOnCanvas(
                    item: item,
                    isGenerating: isGenerating,
                    phase: generationPhase,
                    revealResult: revealResult,
                    heroNamespace: heroNamespace
                )
                TryOnItemInfo(item: item)
                Button(action: { Task { await generate() } }) {
                    Label(
                        store.item(for: item.id)?.tryOnImageData == nil ? "Generate Try-On" : "Regenerate",
                        systemImage: "sparkles"
                    )
                    .symbolEffect(.bounce, value: isGenerating)
                    .primaryButton()
                }
                .disabled(isGenerating)
                .opacity(isGenerating ? 0.4 : 1)
                .scaleEffect(isGenerating ? 0.97 : 1)
                .animation(.spring(duration: 0.35, bounce: 0.3), value: isGenerating)
            }
            .padding(24)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    @MainActor
    private func generate() async {
        revealResult = false
        isGenerating = true

        withAnimation(.spring(duration: 0.5, bounce: 0.25)) {
            generationPhase = .analyzing
        }

        let task = Task { await store.runTryOn(for: item.id) }

        // Drive the UI phase animation in parallel with the network call so
        // the canvas still feels alive while Gemini works. Phases advance on a
        // soft cadence; the real terminal state is set when the task returns.
        await advanceUIPhases()

        let finalState = await task.value
        let success: Bool
        switch finalState {
        case .done: success = true
        case .failed: success = false
        default: success = false
        }

        withAnimation(.spring(duration: 0.6, bounce: 0.35)) {
            generationPhase = success ? .done : .idle
            isGenerating = false
            revealResult = success
        }
    }

    @MainActor
    private func advanceUIPhases() async {
        let cadence: [(GenerationPhase, Duration)] = [
            (.rendering, .milliseconds(900)),
            (.composing, .milliseconds(900))
        ]
        for (phase, dwell) in cadence {
            try? await Task.sleep(for: dwell)
            if !isGenerating { return }
            withAnimation(.spring(duration: 0.5, bounce: 0.25)) {
                generationPhase = phase
            }
        }
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
                    .contentTransition(.interpolate)
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
    let revealResult: Bool
    let heroNamespace: Namespace.ID

    var body: some View {
        ZStack {
            if let latest = store.item(for: item.id),
               let tryOnImage = latest.tryOnUIImage,
               revealResult {
                Image(uiImage: tryOnImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(.rect(cornerRadius: 22))
                    .matchedGeometryEffect(id: "tryon-\(item.id)", in: heroNamespace)
                    .transition(.scale(scale: 0.92).combined(with: .opacity))
            } else if let avatarImage = store.profile.avatarUIImage {
                Image(uiImage: avatarImage)
                    .resizable()
                    .scaledToFill()
                    .clipShape(.rect(cornerRadius: 22))
                    .opacity(isGenerating ? 0.55 : 0.85)
                    .overlay {
                        if !isGenerating {
                            IdlePrompt()
                                .transition(.opacity.combined(with: .scale(scale: 0.9)))
                        }
                    }
            }

            if isGenerating {
                ScanLineOverlay()
                    .clipShape(.rect(cornerRadius: 22))
                    .allowsHitTesting(false)
                PhasePill(phase: phase)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
        .animation(.spring(duration: 0.5, bounce: 0.3), value: isGenerating)
        .animation(.spring(duration: 0.55, bounce: 0.35), value: revealResult)
    }
}

private struct IdlePrompt: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 48, weight: .ultraLight))
                .foregroundStyle(Theme.textMuted)
                .symbolEffect(.pulse, options: .repeating)
            Text("Tap Generate")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

private struct PhasePill: View {
    let phase: TryOnView.GenerationPhase

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: phase.symbol)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.symbolEffect(.replace))
            Text(phase.text)
                .font(.footnote.weight(.medium))
                .foregroundStyle(Theme.textSecondary)
                .contentTransition(.interpolate)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Theme.glassBorder, lineWidth: 1))
        .shadow(color: .black.opacity(0.15), radius: 12, y: 2)
    }
}

private struct ScanLineOverlay: View {
    @State private var sweepY: CGFloat = 0

    var body: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            ZStack {
                LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.45),
                        Color.white.opacity(0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 80)
                .blur(radius: 6)
                .offset(y: sweepY - height / 2)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .task {
                sweepY = 0
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    sweepY = height
                }
            }
        }
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

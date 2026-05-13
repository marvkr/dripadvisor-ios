import SwiftUI

enum Theme {
    static let bg = Color(red: 0.976, green: 0.961, blue: 0.941)

    static let textPrimary = Color.black.opacity(0.9)
    static let textBody = Color.black.opacity(0.8)
    static let textSecondary = Color.black.opacity(0.7)
    static let textMuted = Color.black.opacity(0.4)
    static let textDisabled = Color.black.opacity(0.3)

    static let glass = Color.white.opacity(0.1)
    static let glassStrong = Color.white.opacity(0.6)
    static let glassBorder = Color.white.opacity(0.6)
    static let glassBorderLight = Color.white.opacity(0.2)

    static let buttonPrimary = Color.black.opacity(0.8)
    static let buttonSecondaryBorder = Color.black.opacity(0.1)

    static let iconActive = Color.black.opacity(0.8)
    static let iconInactive = Color.black.opacity(0.3)

    static let error = Color(red: 0.706, green: 0.235, blue: 0.235).opacity(0.8)
}

// MARK: - View modifiers

extension View {
    nonisolated func glassCard() -> some View {
        self
            .background(.ultraThinMaterial)
            .clipShape(.rect(cornerRadius: 24))
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .strokeBorder(Theme.glassBorder, lineWidth: 1.5)
            )
            .shadow(color: .black.opacity(0.1), radius: 4, y: 0)
    }

    nonisolated func primaryButton() -> some View {
        self
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .background(Theme.buttonPrimary)
            .clipShape(Capsule())
    }

    nonisolated func secondaryButton() -> some View {
        self
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 24)
            .overlay(Capsule().strokeBorder(Theme.buttonSecondaryBorder, lineWidth: 1.5))
            .clipShape(Capsule())
    }
}

import StoreKit
import SwiftUI

/// Paywall screen using StoreKit 2's `SubscriptionStoreView`. Visual design
/// follows the grill's Lensa-inspired spec: anchored discount, 7-day trial
/// toggle, social-proof bullet list above the buttons.
struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss

    private let subscriptionGroupID = "dripadvisor.pro"

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Unlock your\nStyle DNA.")
                            .font(.system(size: 36, weight: .bold, design: .serif))
                            .foregroundStyle(Theme.textPrimary)

                        VStack(alignment: .leading, spacing: 10) {
                            bulletRow("Unlimited AI try-ons")
                            bulletRow("Full Stylist chat + group chats")
                            bulletRow("No watermark on shared outfits")
                            bulletRow("Priority on new features")
                        }
                        .padding(.top, 6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 20)
                }

                SubscriptionStoreView(groupID: subscriptionGroupID) {
                    EmptyView()
                }
                .storeButton(.visible, for: .restorePurchases)
                .storeButton(.visible, for: .cancellation)
                .subscriptionStoreControlStyle(.prominentPicker)
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
                .onInAppPurchaseCompletion { _, result in
                    if case .success(.success) = result {
                        dismiss()
                    }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            Button(action: dismiss.callAsFunction) {
                Image(systemName: "xmark")
                    .font(.footnote.bold())
                    .foregroundStyle(Theme.textSecondary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(.top, 12)
            .padding(.trailing, 16)
        }
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Theme.buttonPrimary)
            Text(text)
                .font(.body)
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

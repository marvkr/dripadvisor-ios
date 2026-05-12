import Foundation
import Observation
import StoreKit

/// Tracks the user's Pro entitlement by listening to StoreKit 2 transaction updates.
/// iOS 17+ pattern per WWDC23 — no receipt file parsing, no server-side verification
/// needed for the v1 slice.
@MainActor
@Observable
final class EntitlementStore {
    /// Product IDs configured in StoreKit configuration + App Store Connect.
    enum Plan: String, CaseIterable {
        case annual = "com.dripadvisor.pro.annual"
        case monthly = "com.dripadvisor.pro.monthly"
        case lifetime = "com.dripadvisor.pro.lifetime"
    }

    private(set) var isPro: Bool = false
    private(set) var activeProductID: String?

    private var updatesTask: Task<Void, Never>?

    init() {
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.process(verification: update)
            }
        }
        Task { [weak self] in
            await self?.refreshCurrentEntitlements()
        }
    }

    func refreshCurrentEntitlements() async {
        var pro = false
        var active: String?
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let tx) = entitlement {
                if Plan(rawValue: tx.productID) != nil, tx.revocationDate == nil {
                    pro = true
                    active = tx.productID
                    break
                }
            }
        }
        self.isPro = pro
        self.activeProductID = active
    }

    private func process(verification: VerificationResult<Transaction>) async {
        if case .verified(let tx) = verification {
            await tx.finish()
            await refreshCurrentEntitlements()
        }
    }
}

import Foundation

/// WardrobeSync bridges the local `DripStore` wardrobe with the backend.
/// v1 strategy: optimistic local insert + background HTTP push on save.
/// If the push fails, the local copy persists and is retried on next sync.
///
/// This is the minimal wiring for Q1 offline-first: local writes are the
/// source-of-truth during the session; the server catches up asynchronously.
@MainActor
final class WardrobeSync {
    private let api: DripAPI
    private(set) var pending: [WardrobeItem] = []

    var pendingCount: Int { pending.count }

    init(api: DripAPI) { self.api = api }

    /// Called after a local insert completes. Pushes to backend; re-queues on failure.
    func pushAfterInsert(_ item: WardrobeItem) async {
        let req = DripAPI.AddWardrobeRequest(
            name: item.name,
            brand: item.brand,
            category: item.category.rawValue,
            imageUrl: nil,
            tags: []
        )
        do {
            _ = try await api.addWardrobe(req)
        } catch {
            pending.append(item)
        }
    }

    /// Retries all queued items. Called on network recovery / app foreground.
    func retryPending() async {
        guard !pending.isEmpty else { return }
        let toRetry = pending
        pending.removeAll()
        for item in toRetry {
            await pushAfterInsert(item)
        }
    }

    /// Loads the authoritative list from backend. Called on login / app foreground.
    func pullLatest() async throws -> [DripAPI.WardrobeItemDTO] {
        try await api.listWardrobe()
    }
}

import Foundation
import Observation
import SwiftUI

@MainActor @Observable
final class DripStore {
    var profile = UserProfile()
    var wardrobe: [WardrobeItem] = []
    var outfits: [Outfit] = []
    var messages: [ChatMessage] = [
        ChatMessage(
            role: .stylist,
            text: "Hey! I'm your style agent. Add a few items to your wardrobe and then ask me what to wear. Try: \"rooftop dinner tonight\""
        )
    ]
    var isOnboarded: Bool { profile.avatarData != nil }
    var isStylistThinking: Bool = false

    /// Optional backend sync bridge. When non-nil, wardrobe inserts are pushed
    /// asynchronously to the backend via `WardrobeSync`. Nil in tests / offline v0.
    var sync: WardrobeSync?

    /// Optional real try-on service. When non-nil, `runTryOn` hits the backend
    /// + Gemini Nano Banana Pro. When nil, falls back to the local
    /// `simulateTryOn` stub (avatar copied to tryOn slot, no compositing).
    var tryOn: TryOnService?

    enum TryOnState: Equatable {
        case idle
        case uploading
        case generating
        case finalizing
        case done
        case failed(String)
    }

    var tryOnState: TryOnState = .idle

    // MARK: Avatar

    func setAvatar(_ data: Data) {
        profile.avatarData = data
    }

    func clearAvatar() {
        profile.avatarData = nil
    }

    // MARK: Wardrobe

    func addItem(_ item: WardrobeItem) {
        wardrobe.insert(item, at: 0)
        if let sync {
            Task { await sync.pushAfterInsert(item) }
        }
    }

    /// Merge server-authoritative items into the local wardrobe.
    /// Replaces any existing entry with the same id; keeps locally-only items that
    /// haven't finished syncing yet.
    func hydrateWardrobe(from remote: [DripAPI.WardrobeItemDTO]) {
        let mapped = remote.compactMap { dto -> WardrobeItem? in
            guard let cat = GarmentCategory(rawValue: dto.category) else { return nil }
            return WardrobeItem(
                id: dto.id,
                name: dto.name,
                brand: dto.brand,
                category: cat,
                createdAt: dto.createdAt
            )
        }
        let localOnly = wardrobe.filter { local in !mapped.contains(where: { $0.id == local.id }) }
        wardrobe = (mapped + localOnly).sorted { $0.createdAt > $1.createdAt }
    }

    func removeItem(_ item: WardrobeItem) {
        wardrobe.removeAll { $0.id == item.id }
        for index in outfits.indices {
            if outfits[index].topID == item.id { outfits[index].topID = nil }
            if outfits[index].bottomID == item.id { outfits[index].bottomID = nil }
            if outfits[index].shoesID == item.id { outfits[index].shoesID = nil }
        }
        outfits.removeAll { $0.topID == nil && $0.bottomID == nil && $0.shoesID == nil }
    }

    func item(for id: UUID?) -> WardrobeItem? {
        guard let id else { return nil }
        return wardrobe.first { $0.id == id }
    }

    func items(in category: GarmentCategory) -> [WardrobeItem] {
        wardrobe.filter { $0.category == category }
    }

    // MARK: Try-on

    /// Runs a real try-on if `tryOn` service is wired; otherwise falls back to
    /// the local stub. Returns the new state of `tryOnState`.
    @discardableResult
    func runTryOn(for itemID: UUID, occasion: String? = nil) async -> TryOnState {
        guard let index = wardrobe.firstIndex(where: { $0.id == itemID }) else {
            tryOnState = .failed("Item not found")
            return tryOnState
        }
        guard let avatarData = profile.avatarData else {
            tryOnState = .failed("Set up your avatar first")
            return tryOnState
        }
        guard let garmentData = wardrobe[index].imageData else {
            tryOnState = .failed("Item has no image")
            return tryOnState
        }

        if let tryOn {
            tryOnState = .uploading
            do {
                tryOnState = .generating
                let result = try await tryOn.compose(
                    avatarData: avatarData,
                    garmentData: garmentData,
                    occasion: occasion
                )
                tryOnState = .finalizing
                wardrobe[index].tryOnImageData = result.imageData
                tryOnState = .done
            } catch {
                tryOnState = .failed(error.localizedDescription)
            }
            return tryOnState
        }

        // Local stub fallback (no backend wired).
        try? await Task.sleep(for: .seconds(1.4))
        wardrobe[index].tryOnImageData = wardrobe[index].imageData ?? profile.avatarData
        tryOnState = .done
        return tryOnState
    }

    /// Back-compat shim for the original stub call site. Kept until views
    /// migrate to `runTryOn`.
    func simulateTryOn(for itemID: UUID) async {
        await runTryOn(for: itemID)
    }

    // MARK: Outfits

    func saveOutfit(_ outfit: Outfit) {
        outfits.insert(outfit, at: 0)
    }

    func removeOutfit(_ outfit: Outfit) {
        outfits.removeAll { $0.id == outfit.id }
    }

    // MARK: Style Agent

    func sendUserMessage(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        Task { await streamStylistReply(to: trimmed) }
    }

    private func streamStylistReply(to prompt: String) async {
        isStylistThinking = true
        defer { isStylistThinking = false }
        try? await Task.sleep(for: .milliseconds(700))

        let reply = buildStylistReply(for: prompt)
        let suggestedIDs = recommendOutfitIDs(for: prompt)

        var streamed = ""
        let message = ChatMessage(role: .stylist, text: "", suggestedItemIDs: suggestedIDs)
        messages.append(message)

        for word in reply.split(separator: " ") {
            streamed += (streamed.isEmpty ? "" : " ") + word
            if let idx = messages.firstIndex(where: { $0.id == message.id }) {
                messages[idx].text = streamed
            }
            try? await Task.sleep(for: .milliseconds(55))
        }
    }

    private func buildStylistReply(for prompt: String) -> String {
        let lower = prompt.lowercased()
        let (top, bottom) = recommendedPair(for: lower)

        if wardrobe.isEmpty {
            return "Your wardrobe is empty — add a few pieces from the Wardrobe tab and I'll build a look you'll love."
        }

        let occasion = detectOccasion(in: lower)
        var parts: [String] = ["For \(occasion) I'd pull together"]

        if let top, let bottom {
            parts.append("the \(top.name) by \(top.brand) with the \(bottom.name) from \(bottom.brand).")
            parts.append("It hits the right balance — elevated without trying too hard.")
        } else if let top {
            parts.append("the \(top.name) by \(top.brand).")
            parts.append("Pair it with your favorite denim and you're set.")
        } else if let bottom {
            parts.append("the \(bottom.name) from \(bottom.brand).")
            parts.append("Layer a fitted tee and sleek sneakers.")
        } else {
            parts.append("something from your wardrobe — tap an item in the Wardrobe tab to try it on.")
        }

        parts.append("Tap Try On to see it on you.")
        return parts.joined(separator: " ")
    }

    private func recommendedPair(for prompt: String) -> (WardrobeItem?, WardrobeItem?) {
        let tops = items(in: .top)
        let bottoms = items(in: .bottom)
        let seed = prompt.unicodeScalars.map { Int($0.value) }.reduce(0, +)
        let top = tops.isEmpty ? nil : tops[seed % tops.count]
        let bottom = bottoms.isEmpty ? nil : bottoms[seed % bottoms.count]
        return (top, bottom)
    }

    private func recommendOutfitIDs(for prompt: String) -> [UUID] {
        let (top, bottom) = recommendedPair(for: prompt.lowercased())
        return [top?.id, bottom?.id].compactMap { $0 }
    }

    private func detectOccasion(in prompt: String) -> String {
        if prompt.contains("rooftop") || prompt.contains("dinner") { return "a rooftop dinner" }
        if prompt.contains("date") { return "a date night" }
        if prompt.contains("work") || prompt.contains("office") { return "the office" }
        if prompt.contains("gym") || prompt.contains("workout") { return "a workout" }
        if prompt.contains("wedding") { return "a wedding" }
        if prompt.contains("casual") || prompt.contains("chill") { return "a casual day out" }
        if prompt.contains("brunch") { return "brunch" }
        if prompt.contains("party") || prompt.contains("club") { return "a night out" }
        return "that vibe"
    }
}

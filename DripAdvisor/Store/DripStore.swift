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

    // MARK: Try-on simulation

    func simulateTryOn(for itemID: UUID) async {
        guard let index = wardrobe.firstIndex(where: { $0.id == itemID }) else { return }
        try? await Task.sleep(for: .seconds(1.4))
        wardrobe[index].tryOnImageData = wardrobe[index].imageData ?? profile.avatarData
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

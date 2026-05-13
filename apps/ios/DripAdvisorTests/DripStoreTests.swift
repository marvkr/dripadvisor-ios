import Testing
@testable import DripAdvisor
import Foundation

@MainActor
@Suite("DripStore — wardrobe")
struct DripStoreWardrobeTests {

    @Test("addItem inserts at head")
    func addItemInsertsAtHead() {
        let store = DripStore()
        let first = WardrobeItem(name: "Oversized Hoodie", brand: "Lululemon", category: .top)
        let second = WardrobeItem(name: "Wide-Leg Trouser", brand: "Aritzia", category: .bottom)

        store.addItem(first)
        store.addItem(second)

        #expect(store.wardrobe.count == 2)
        #expect(store.wardrobe[0].id == second.id)
        #expect(store.wardrobe[1].id == first.id)
    }

    @Test("removeItem deletes by id and cleans outfits that become empty")
    func removeItemCleansOrphanedOutfits() {
        let store = DripStore()
        let top = WardrobeItem(name: "Tee", brand: "Uniqlo", category: .top)
        store.addItem(top)

        let outfit = Outfit(name: "Casual look", topID: top.id)
        store.saveOutfit(outfit)

        store.removeItem(top)

        #expect(store.wardrobe.isEmpty)
        #expect(store.outfits.isEmpty, "Outfit with no remaining items should be removed")
    }

    @Test("removeItem keeps partial outfits that still reference other items")
    func removeItemKeepsPartialOutfit() {
        let store = DripStore()
        let top = WardrobeItem(name: "Tee", brand: "Uniqlo", category: .top)
        let bottom = WardrobeItem(name: "Jeans", brand: "Levi's", category: .bottom)
        store.addItem(top)
        store.addItem(bottom)

        let outfit = Outfit(name: "Classic fit", topID: top.id, bottomID: bottom.id)
        store.saveOutfit(outfit)

        store.removeItem(top)

        #expect(store.outfits.count == 1)
        #expect(store.outfits[0].topID == nil)
        #expect(store.outfits[0].bottomID == bottom.id)
    }

    @Test("items(in:) filters by category")
    func itemsInCategoryFilters() {
        let store = DripStore()
        store.addItem(WardrobeItem(name: "Tee", brand: "Uniqlo", category: .top))
        store.addItem(WardrobeItem(name: "Jeans", brand: "Levi's", category: .bottom))
        store.addItem(WardrobeItem(name: "Sneakers", brand: "Nike", category: .shoes))

        #expect(store.items(in: .top).count == 1)
        #expect(store.items(in: .bottom).count == 1)
        #expect(store.items(in: .shoes).count == 1)
        #expect(store.items(in: .outerwear).isEmpty)
    }

    @Test("item(for:) returns matching item or nil")
    func itemForIdResolvesCorrectly() {
        let store = DripStore()
        let item = WardrobeItem(name: "Tee", brand: "Uniqlo", category: .top)
        store.addItem(item)

        #expect(store.item(for: item.id)?.id == item.id)
        #expect(store.item(for: UUID()) == nil)
        #expect(store.item(for: nil) == nil)
    }
}

@MainActor
@Suite("DripStore — avatar + onboarding")
struct DripStoreAvatarTests {

    @Test("isOnboarded flips once avatar data is set")
    func onboardedFlipsWithAvatar() {
        let store = DripStore()
        #expect(store.isOnboarded == false)

        store.setAvatar(Data([0x01, 0x02, 0x03]))
        #expect(store.isOnboarded == true)

        store.clearAvatar()
        #expect(store.isOnboarded == false)
    }
}

@MainActor
@Suite("DripStore — chat")
struct DripStoreChatTests {

    @Test("seeded stylist message is present")
    func seededStylistMessagePresent() {
        let store = DripStore()
        #expect(store.messages.count == 1)
        #expect(store.messages.first?.role == .stylist)
    }

    @Test("sendUserMessage appends user message and trims whitespace")
    func sendUserMessageAppendsTrimmed() {
        let store = DripStore()
        store.sendUserMessage("   rooftop dinner tonight   ")

        let userMessages = store.messages.filter { $0.role == .user }
        #expect(userMessages.count == 1)
        #expect(userMessages.first?.text == "rooftop dinner tonight")
    }

    @Test("sendUserMessage ignores whitespace-only input")
    func sendUserMessageIgnoresEmpty() {
        let store = DripStore()
        let before = store.messages.count
        store.sendUserMessage("   \n  ")
        #expect(store.messages.count == before)
    }
}

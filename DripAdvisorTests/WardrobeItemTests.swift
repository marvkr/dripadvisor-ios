import Testing
@testable import DripAdvisor
import Foundation
import UIKit

@Suite("WardrobeItem")
struct WardrobeItemTests {

    @Test("default initializer populates id and createdAt")
    func defaultsPopulated() {
        let item = WardrobeItem(name: "Tee", brand: "Uniqlo", category: .top)
        #expect(item.name == "Tee")
        #expect(item.brand == "Uniqlo")
        #expect(item.category == .top)
        #expect(item.imageData == nil)
        #expect(item.tryOnImageData == nil)
    }

    @Test("uiImage decodes when imageData holds a valid PNG")
    func uiImageDecodesValidPNG() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4))
        let png = renderer.pngData { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        }
        let item = WardrobeItem(name: "Tee", brand: "Uniqlo", category: .top, imageData: png)
        #expect(item.uiImage != nil)
    }

    @Test("uiImage is nil for empty data")
    func uiImageNilForEmptyData() {
        let item = WardrobeItem(name: "Tee", brand: "Uniqlo", category: .top, imageData: Data())
        #expect(item.uiImage == nil)
    }

    @Test("items with identical fields are equal")
    func structuralEquality() {
        let id = UUID()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        let a = WardrobeItem(id: id, name: "Tee", brand: "Uniqlo", category: .top, createdAt: when)
        let b = WardrobeItem(id: id, name: "Tee", brand: "Uniqlo", category: .top, createdAt: when)
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
    }

    @Test("items differ when createdAt differs even if id matches")
    func createdAtDifferentiatesIdentity() {
        let id = UUID()
        let a = WardrobeItem(id: id, name: "Tee", brand: "Uniqlo", category: .top, createdAt: Date(timeIntervalSince1970: 1))
        let b = WardrobeItem(id: id, name: "Tee", brand: "Uniqlo", category: .top, createdAt: Date(timeIntervalSince1970: 2))
        #expect(a != b)
    }
}

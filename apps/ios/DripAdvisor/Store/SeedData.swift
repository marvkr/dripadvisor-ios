#if DEBUG
import SwiftUI
import UIKit

/// Demo seed used in DEBUG builds. Populates the wardrobe with 6 garments
/// (2 tops, 2 bottoms, 2 shoes) and 2 outfits so the whole flow — wardrobe
/// → try-on → outfit → share — is exercisable without going through
/// onboarding + Apple Sign In + Gemini try-on.
enum SeedData {

    struct GarmentSpec {
        let name: String
        let brand: String
        let category: GarmentCategory
        let primary: UIColor
        let glyph: String   // SF Symbol name drawn on the cutout
        let color: String   // human color label
        let retailPrice: Double?
        let source: WardrobeItemSource
    }

    static let beige = UIColor(red: 0.83, green: 0.78, blue: 0.65, alpha: 1)
    static let tan   = UIColor(red: 0.72, green: 0.58, blue: 0.43, alpha: 1)

    static let garments: [GarmentSpec] = [
        .init(name: "Crewneck Tee",      brand: "Uniqlo",     category: .top,    primary: .systemTeal,    glyph: "tshirt.fill",  color: "teal",    retailPrice: 19,  source: .owned),
        .init(name: "Linen Shirt",       brand: "COS",        category: .top,    primary: beige,          glyph: "tshirt",       color: "beige",   retailPrice: 89,  source: .owned),
        .init(name: "Slim Denim",        brand: "Levi's 511", category: .bottom, primary: .systemIndigo,  glyph: "figure.walk",  color: "indigo",  retailPrice: 95,  source: .owned),
        .init(name: "Tailored Shorts",   brand: "Aritzia",    category: .bottom, primary: .darkGray,      glyph: "figure.walk",  color: "charcoal",retailPrice: 70,  source: .wishlist),
        .init(name: "Court Sneakers",    brand: "Adidas Stan",category: .shoes,  primary: .white,         glyph: "shoe.fill",    color: "white",   retailPrice: 110, source: .owned),
        .init(name: "Suede Runners",     brand: "New Balance",category: .shoes,  primary: tan,            glyph: "shoe.fill",    color: "tan",     retailPrice: 140, source: .wishlist),
    ]

    struct OutfitSpec {
        let occasion: String
        let tint: UIColor
        let glyph: String
    }

    static let outfits: [OutfitSpec] = [
        .init(occasion: "Weekend Brunch",  tint: beige,         glyph: "sun.max.fill"),
        .init(occasion: "Evening Drinks",  tint: .systemIndigo, glyph: "moon.stars.fill"),
    ]

    /// Builds WardrobeItem + Outfit objects with synthesized PNG image data.
    /// Returns nil when image rendering fails (shouldn't happen on device).
    @MainActor
    static func build() -> (wardrobe: [WardrobeItem], outfits: [Outfit]) {
        let wardrobe = garments.map { spec -> WardrobeItem in
            let png = render(color: spec.primary, glyph: spec.glyph, label: spec.name, size: CGSize(width: 600, height: 800))
            return WardrobeItem(
                name: spec.name,
                brand: spec.brand,
                category: spec.category,
                imageData: png,
                source: spec.source,
                retailPrice: spec.retailPrice,
                currency: spec.retailPrice == nil ? nil : "USD",
                color: spec.color,
                tags: ["seed"]
            )
        }
        let tops    = wardrobe.filter { $0.category == .top }
        let bottoms = wardrobe.filter { $0.category == .bottom }
        let shoes   = wardrobe.filter { $0.category == .shoes }

        let outfits = outfits.enumerated().map { i, spec -> Outfit in
            _ = render(color: spec.tint, glyph: spec.glyph, label: spec.occasion, size: CGSize(width: 800, height: 1200))
            return Outfit(
                name: spec.occasion,
                occasion: spec.occasion,
                topID: tops[safe: i]?.id ?? tops.first?.id,
                bottomID: bottoms[safe: i]?.id ?? bottoms.first?.id,
                shoesID: shoes[safe: i]?.id ?? shoes.first?.id
            )
        }
        return (wardrobe, outfits)
    }

}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

extension SeedData {
    /// Renders the SF Symbol glyph alone on a fully transparent canvas so
    /// the cutout's alpha channel matches the glyph's silhouette. StickerImage
    /// then dilates that alpha into a clean white contour — true sticker shape,
    /// not a square placeholder.
    static func render(color: UIColor, glyph: String, label: String, size: CGSize) -> Data? {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.pngData { _ in
            let cfg = UIImage.SymbolConfiguration(pointSize: size.width * 0.7, weight: .semibold)
            guard let symbol = UIImage(systemName: glyph, withConfiguration: cfg)?
                .withTintColor(color, renderingMode: .alwaysOriginal)
            else { return }
            let s = symbol.size
            symbol.draw(at: CGPoint(
                x: (size.width  - s.width)  / 2,
                y: (size.height - s.height) / 2
            ))
        }
    }
}
#endif

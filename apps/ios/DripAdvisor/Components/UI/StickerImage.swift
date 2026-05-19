import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

/// Renders a background-removed image as a Telegram-style sticker:
/// dilated white contour around the alpha mask + soft drop shadow.
///
/// Caches the stickerized version per source image to avoid re-running
/// Core Image on every redraw.
struct StickerImage: View {
    let uiImage: UIImage
    var borderWidth: CGFloat = 6
    var shadowRadius: CGFloat = 6

    @State private var rendered: UIImage?

    var body: some View {
        Group {
            if let rendered {
                Image(uiImage: rendered)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .opacity(0.0)
            }
        }
        .shadow(color: .black.opacity(0.18), radius: shadowRadius, x: 0, y: shadowRadius / 2)
        .task(id: uiImage.hashValue) {
            rendered = await Self.stickerize(uiImage, border: borderWidth)
        }
    }

    private static func stickerize(_ src: UIImage, border: CGFloat) async -> UIImage? {
        await Task.detached(priority: .userInitiated) {
            let context = CIContext(options: [.useSoftwareRenderer: false])
            guard let cg = src.cgImage else { return nil }
            let base = CIImage(cgImage: cg)
            let dilate = CIFilter.morphologyMaximum()
            dilate.inputImage = base
            dilate.radius = Float(border)
            guard let dilated = dilate.outputImage else { return nil }
            let mask = CIFilter.maskToAlpha()
            mask.inputImage = dilated
            guard let whiteMask = mask.outputImage else { return nil }
            let whiteFill = CIImage(color: .white).cropped(to: whiteMask.extent)
            let masked = whiteFill.applyingFilter("CIBlendWithAlphaMask",
                parameters: [kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: whiteMask.extent),
                             kCIInputMaskImageKey: whiteMask])
            let composite = base.composited(over: masked)
            guard let out = context.createCGImage(composite, from: composite.extent) else { return nil }
            return UIImage(cgImage: out, scale: src.scale, orientation: src.imageOrientation)
        }.value
    }
}

/// Caption pill that looks like a die-cut sticker label.
struct StickerLabel: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .heavy))
            .foregroundStyle(Theme.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                Capsule()
                    .fill(.white)
                    .overlay(Capsule().strokeBorder(.white, lineWidth: 2))
            )
            .shadow(color: .black.opacity(0.15), radius: 3, x: 0, y: 1)
    }
}

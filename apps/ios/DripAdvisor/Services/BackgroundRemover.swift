import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit
import Vision

enum BackgroundRemovalError: Error {
    case invalidImage
    case noSubjectDetected
    case renderFailed
}

/// On-device background removal via Apple Vision (iOS 17+).
/// Produces a transparent-background PNG using VNGenerateForegroundInstanceMaskRequest
/// + CIFilter.blendWithMask.
enum BackgroundRemover {
    static func removeBackground(from image: UIImage) async throws -> Data {
        guard let ciInput = CIImage(image: image) else {
            throw BackgroundRemovalError.invalidImage
        }
        let mask = try await generateMask(for: ciInput)
        let masked = applyMask(mask, to: ciInput)
        guard let pngData = render(masked) else {
            throw BackgroundRemovalError.renderFailed
        }
        return pngData
    }

    private static func generateMask(for input: CIImage) async throws -> CIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(ciImage: input)
        try handler.perform([request])
        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            throw BackgroundRemovalError.noSubjectDetected
        }
        let maskBuffer = try result.generateScaledMaskForImage(
            forInstances: result.allInstances,
            from: handler
        )
        return CIImage(cvPixelBuffer: maskBuffer)
    }

    private static func applyMask(_ mask: CIImage, to image: CIImage) -> CIImage {
        let filter = CIFilter.blendWithMask()
        filter.inputImage = image
        filter.maskImage = mask
        filter.backgroundImage = .empty()
        return filter.outputImage ?? image
    }

    private static func render(_ image: CIImage) -> Data? {
        let context = CIContext(options: nil)
        guard let cgImage = context.createCGImage(image, from: image.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage).pngData()
    }
}

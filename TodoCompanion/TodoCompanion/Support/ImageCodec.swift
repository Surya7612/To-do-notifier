import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum ImageCodec {
    /// Screenshots are stored and sent downscaled: full-resolution Retina grabs
    /// are several megabytes each and add nothing for OCR or a vision model.
    nonisolated static func pngData(from image: CGImage, maxDimension: CGFloat = 1600) -> Data? {
        let resized = downscale(image, maxDimension: maxDimension) ?? image
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil
        ) else { return nil }
        CGImageDestinationAddImage(destination, resized, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    nonisolated static func base64PNG(from image: CGImage, maxDimension: CGFloat = 1568) -> String? {
        pngData(from: image, maxDimension: maxDimension)?.base64EncodedString()
    }

    nonisolated static func downscale(_ image: CGImage, maxDimension: CGFloat) -> CGImage? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let scale = min(1, maxDimension / max(width, height))
        guard scale < 1 else { return image }

        let newWidth = Int(width * scale)
        let newHeight = Int(height * scale)
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage()
    }
}

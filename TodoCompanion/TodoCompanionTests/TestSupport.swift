import CoreGraphics
import Foundation
@testable import TodoCompanion

/// Builders for the values these tests need. Kept in one place so a test reads
/// as the thing it is checking rather than as setup.
enum Fixture {
    /// An image whose top half is white and bottom half is black.
    ///
    /// The halves matter: a crop that ignores the difference between AppKit's
    /// bottom-left origin and CoreGraphics' top-left one still returns a
    /// correctly *sized* image, so only the pixels can catch a vertical flip.
    ///
    /// Row 0 of a `CGImage` is its top row, so the first half of the buffer is
    /// the white half.
    static func splitImage(width: Int, height: Int) -> CGImage {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0..<height {
            let value: UInt8 = row < height / 2 ? 255 : 0
            for column in 0..<width {
                let offset = (row * width + column) * 4
                bytes[offset] = value
                bytes[offset + 1] = value
                bytes[offset + 2] = value
                bytes[offset + 3] = 255
            }
        }
        return image(from: bytes, width: width, height: height)
    }

    /// A uniformly mid-grey image, for tests that need pixels but do not care
    /// what is in them.
    static func blankImage(width: Int = 16, height: Int = 16) -> CGImage {
        let bytes = [UInt8](repeating: 128, count: width * height * 4)
        return image(from: bytes, width: width, height: height)
    }

    private static func image(from bytes: [UInt8], width: Int, height: Int) -> CGImage {
        let provider = CGDataProvider(data: Data(bytes) as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )!
    }

    static func observation(
        image: CGImage? = nil,
        text: String = "",
        app: String? = nil,
        window: String? = nil,
        others: [CapturedDisplay] = []
    ) -> ScreenObservation {
        ScreenObservation(
            primary: CapturedDisplay(image: image ?? blankImage(), index: 1, recognizedText: text),
            others: others,
            appName: app,
            windowTitle: window
        )
    }

    static func saved(
        intent: String,
        app: String = "",
        window: String = "",
        topics: [String] = [],
        daysOld: Double = 0
    ) -> SavedContext {
        let context = SavedContext(intent: intent, sourceApp: app, windowTitle: window, topics: topics)
        context.createdAt = Date().addingTimeInterval(-daysOld * 86_400)
        return context
    }
}

extension CGImage {
    /// Brightness of the pixel at the top-left corner, 0...1.
    ///
    /// Re-rendered into a fresh buffer rather than read from `dataProvider`,
    /// because `cropping(to:)` can hand back an image that still points at the
    /// full original pixels with only its bounds narrowed.
    var topLeftBrightness: Double {
        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return -1 }

        // Drawing the whole image into a 1x1 context averages it, which is what
        // we want: these fixtures are uniform within the region under test.
        context.draw(self, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Double(pixel[0]) / 255.0
    }
}

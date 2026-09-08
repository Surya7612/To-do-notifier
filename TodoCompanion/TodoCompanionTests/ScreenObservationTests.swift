import CoreGraphics
import Testing
@testable import TodoCompanion

/// The region crop converts between two coordinate systems and a pixel scale
/// factor. It is the piece of this app most likely to be quietly wrong, and the
/// hardest to check by looking at the screen, because a flipped crop still
/// produces a plausible picture of something else.
@Suite("Region cropping")
struct ScreenObservationTests {
    /// A 100x100pt display captured at 2x.
    private let displayFrame = CGRect(x: 0, y: 0, width: 100, height: 100)

    private func observation() -> ScreenObservation {
        Fixture.observation(image: Fixture.splitImage(width: 200, height: 200))
    }

    @Test("a selection at the top of the screen returns the top of the image")
    func topSelectionIsTopOfImage() throws {
        // AppKit's y grows upward, so the top half of this display is y 50...100.
        let selection = CGRect(x: 0, y: 50, width: 50, height: 50)
        let cropped = try #require(observation().cropped(to: selection, inDisplayFrame: displayFrame))

        #expect(cropped.image.width == 100)
        #expect(cropped.image.height == 100)
        #expect(cropped.image.topLeftBrightness > 0.9, "expected the white half")
    }

    @Test("a selection at the bottom of the screen returns the bottom of the image")
    func bottomSelectionIsBottomOfImage() throws {
        let selection = CGRect(x: 0, y: 0, width: 50, height: 50)
        let cropped = try #require(observation().cropped(to: selection, inDisplayFrame: displayFrame))

        #expect(cropped.image.topLeftBrightness < 0.1, "expected the black half")
    }

    @Test("the backing scale is applied to the selection")
    func selectionIsScaledToPixels() throws {
        let selection = CGRect(x: 10, y: 20, width: 30, height: 40)
        let cropped = try #require(observation().cropped(to: selection, inDisplayFrame: displayFrame))

        // 200px / 100pt = 2x.
        #expect(cropped.image.width == 60)
        #expect(cropped.image.height == 80)
    }

    @Test("a display with a non-zero origin is offset correctly")
    func secondaryDisplayOriginIsSubtracted() throws {
        // A second monitor sitting to the right of the built-in one. Its
        // selections arrive in global coordinates, so the display's own origin
        // has to come out or the crop lands off the edge of the image.
        let frame = CGRect(x: 1440, y: 0, width: 100, height: 100)
        let selection = CGRect(x: 1440, y: 50, width: 50, height: 50)
        let cropped = try #require(observation().cropped(to: selection, inDisplayFrame: frame))

        #expect(cropped.image.width == 100)
        #expect(cropped.image.topLeftBrightness > 0.9, "expected the top-left of the image")
    }

    @Test("a selection running past the edge is clamped to the image")
    func oversizedSelectionIsClamped() throws {
        let selection = CGRect(x: 60, y: 60, width: 500, height: 500)
        let cropped = try #require(observation().cropped(to: selection, inDisplayFrame: displayFrame))

        #expect(cropped.image.width <= 200)
        #expect(cropped.image.height <= 200)
    }

    @Test("a selection too small to read is refused")
    func tinySelectionIsRejected() {
        let selection = CGRect(x: 10, y: 10, width: 2, height: 2)
        #expect(observation().cropped(to: selection, inDisplayFrame: displayFrame) == nil)
    }

    @Test("an empty display frame is refused rather than dividing by zero")
    func emptyFrameIsRejected() {
        let selection = CGRect(x: 0, y: 0, width: 50, height: 50)
        #expect(observation().cropped(to: selection, inDisplayFrame: .zero) == nil)
    }

    @Test("cropping marks the observation and drops other displays")
    func croppingNarrowsToOneDisplay() throws {
        var source = observation()
        source.others = [CapturedDisplay(image: Fixture.blankImage(), index: 2, recognizedText: "other monitor")]

        let cropped = try #require(source.cropped(to: CGRect(x: 0, y: 50, width: 50, height: 50),
                                                  inDisplayFrame: displayFrame))

        #expect(cropped.isCropped)
        #expect(cropped.others.isEmpty, "text from another monitor is noise once a region is chosen")
        #expect(!cropped.recognizedText.contains("other monitor"))
    }

    @Test("multi-display text is labelled so the model can tell them apart")
    func multiDisplayTextIsLabelled() {
        let observation = Fixture.observation(
            text: "focused text",
            others: [CapturedDisplay(image: Fixture.blankImage(), index: 2, recognizedText: "second text")]
        )

        #expect(observation.recognizedText.contains("[Display 1 — focused]"))
        #expect(observation.recognizedText.contains("[Display 2]"))
    }

    @Test("a single display's text is passed through unlabelled")
    func singleDisplayTextIsBare() {
        #expect(Fixture.observation(text: "just this").recognizedText == "just this")
    }

    @Test("the context label degrades gracefully as metadata goes missing")
    func contextLabelHandlesMissingMetadata() {
        #expect(Fixture.observation(app: "Xcode", window: "ScreenCapture.swift").contextLabel
                == "Xcode — ScreenCapture.swift")
        #expect(Fixture.observation(app: "Xcode", window: "").contextLabel == "Xcode")
        #expect(Fixture.observation().contextLabel == "Screen")
    }
}

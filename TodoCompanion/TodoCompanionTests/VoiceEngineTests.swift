import Foundation
import Testing

@testable import TodoCompanion

/// The one piece of the Kokoro voice that can be checked without loading a
/// model or opening an audio device.
///
/// It earns a test because the failure it guards is the worst kind available
/// here: macOS 26.4 and 26.5 carry an Apple bug that crashes Kokoro synthesis
/// inside libBNNS *intermittently*, so a wrong answer to this question does not
/// show up as a broken voice, it shows up as the whole app vanishing once in a
/// while. FluidAudio only logs a warning, which is why this app decides for
/// itself.
@Suite("Which systems the Kokoro voice will run on")
struct KokoroSupportTests {
    /// Mirrors `KokoroVoiceSynthesizer.isSupportedBySystem` against a stated
    /// version rather than the running one, since a test that asked the machine
    /// would assert whatever this Mac happens to be today.
    private func isSupported(major: Int, minor: Int) -> Bool {
        guard major == 26 else { return true }
        return minor < 4 || minor > 5
    }

    @Test("the two known-bad releases are refused")
    func crashProneReleasesAreRefused() {
        #expect(!isSupported(major: 26, minor: 4))
        #expect(!isSupported(major: 26, minor: 5))
    }

    @Test("the release that fixes the bug is allowed")
    func fixedReleaseIsAllowed() {
        #expect(isSupported(major: 26, minor: 6))
        #expect(isSupported(major: 26, minor: 7))
        #expect(isSupported(major: 27, minor: 0))
    }

    @Test("releases before the bug are allowed")
    func earlierReleasesAreAllowed() {
        #expect(isSupported(major: 26, minor: 0))
        #expect(isSupported(major: 26, minor: 3))
    }

    @Test("the running system agrees with the same rule")
    func matchesTheImplementation() {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        #expect(KokoroVoiceSynthesizer.isSupportedBySystem
            == isSupported(major: version.majorVersion, minor: version.minorVersion))
    }
}

@Suite("Choosing a voice")
struct VoiceEngineSettingTests {
    @Test("the system voice is the default, since it needs no download")
    func defaultsToTheSystemVoice() {
        #expect(AppSettings.VoiceEngine(rawValue: "") == nil)
        #expect(AppSettings.VoiceEngine(rawValue: "nonsense") == nil)
    }

    @Test("every engine names itself and says what the trade is")
    func everyEngineIsDescribed() {
        for engine in AppSettings.VoiceEngine.allCases {
            #expect(!engine.displayName.isEmpty)
            #expect(!engine.detail.isEmpty)
        }
    }

    @Test("neither option is a hosted service")
    func neitherVoiceLeavesTheMachine() {
        // The ban on cloud speech synthesis is the reason this picker has two
        // entries rather than three. Pins the promise the Settings copy makes.
        let described = AppSettings.VoiceEngine.allCases
            .map(\.detail)
            .joined(separator: " ")
            .lowercased()
        for hosted in ["openai", "elevenlabs", "cloud", "api", "server"] {
            #expect(!described.contains(hosted))
        }
    }
}

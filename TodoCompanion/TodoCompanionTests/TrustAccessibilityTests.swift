import Foundation
import Testing
@testable import TodoCompanion

@Suite("Accessibility Settings deep links")
struct TrustAccessibilityTests {
    @Test("candidates prefer the macOS 27 Accessibility list URL")
    func prefersPrivacyAccessibilityUTI() {
        let first = TrustAccessibility.accessibilitySettingsURLCandidates.first
        #expect(first ==
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension.privacy-accessibility")
    }

    @Test("candidates include the legacy Privacy_Accessibility query and settings-navigation")
    func includesLegacyAndNavigationSchemes() {
        let all = TrustAccessibility.accessibilitySettingsURLCandidates
        #expect(all.contains {
            $0.contains("Privacy_Accessibility")
        })
        #expect(all.contains {
            $0.hasPrefix("settings-navigation:")
        })
        #expect(all.allSatisfy { URL(string: $0) != nil })
    }
}

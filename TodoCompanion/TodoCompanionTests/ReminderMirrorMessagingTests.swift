import Foundation
import Testing
@testable import TodoCompanion

@Suite("Reminder mirror messaging")
struct ReminderMirrorMessagingTests {
    @Test("the off-state copy says iCloud delivers and there is no custom push")
    func offStateMentionsPhoneAndNoPushServer() {
        let text = ReminderMirrorMessaging.offStateDetail
        #expect(text.contains("iCloud"))
        #expect(text.localizedCaseInsensitiveContains("iPhone") || text.contains("Watch"))
        #expect(text.localizedCaseInsensitiveContains("push"))
    }

    @Test("a syncing destination names the list and the phone")
    func syncingDetailNamesListAndPhone() {
        let text = ReminderMirrorMessaging.detail(
            for: .syncing(account: "iCloud"),
            listTitle: "Max",
            assistantName: "Max"
        )
        #expect(text.contains("Max"))
        #expect(text.contains("iCloud"))
        #expect(text.contains("iPhone") || text.contains("Watch"))
    }

    @Test("a this-Mac-only destination warns that the phone will not hear")
    func thisMacOnlyWarns() {
        let text = ReminderMirrorMessaging.detail(
            for: .thisMacOnly(account: "On My Mac"),
            listTitle: "Max",
            assistantName: "Max"
        )
        #expect(text.contains("On My Mac"))
        #expect(text.localizedCaseInsensitiveContains("does not sync")
                || text.localizedCaseInsensitiveContains("will not reach"))
        #expect(text.contains("System Settings"))
    }

    @Test("denied copy points at System Settings")
    func deniedPointsAtSettings() {
        let text = ReminderMirrorMessaging.deniedDetail(assistantName: "Max")
        #expect(text.contains("System Settings"))
        #expect(text.contains("Reminders"))
        #expect(text.contains("Max"))
    }
}

@Suite("Cloud model choices")
struct CloudModelChoiceTests {
    @Test("Claude lists have no prices in their blurbs")
    func anthropicBlurbsOmitPrices() {
        for choice in AnthropicModelChoice.all {
            #expect(!choice.detail.contains("$"))
            #expect(!choice.detail.localizedCaseInsensitiveContains("per million"))
        }
    }

    @Test("Gemini lists have no prices in their blurbs")
    func geminiBlurbsOmitPrices() {
        for choice in GeminiModelChoice.all {
            #expect(!choice.detail.contains("$"))
            #expect(!choice.detail.localizedCaseInsensitiveContains("per million"))
        }
    }

    @Test("defaults appear in the curated lists")
    func defaultsAreListed() {
        #expect(AnthropicModelChoice.named(AnthropicBrain.defaultModel) != nil)
        #expect(GeminiModelChoice.named(GeminiBrain.defaultModel) != nil)
    }

    @Test("unknown names fall through to Custom")
    func unknownIsCustom() {
        #expect(AnthropicModelChoice.selection(for: "claude-future-99") == .custom)
        #expect(GeminiModelChoice.selection(for: "gemini-future-99") == .custom)
    }
}

@Suite("Cloud prompt wiring")
struct CloudPromptWiringTests {
    /// Each cloud path must still receive the shared Prompt text — persona and
    /// grounding live there, not in the HTTP clients.
    @Test("every cloud brain is labelled as leaving the machine")
    func cloudBrainsLeave() {
        #expect(OpenAIBrain(apiKey: "x", model: "m").leavesTheMachine)
        #expect(AnthropicBrain(apiKey: "x", model: "m").leavesTheMachine)
        #expect(GeminiBrain(apiKey: "x", model: "m").leavesTheMachine)
        #expect(!OllamaBrain(endpoint: URL(string: "http://127.0.0.1:11434")!, model: "m").leavesTheMachine)
    }

    @Test("the shared system prompt still grounds Max")
    func systemPromptStillGrounds() {
        #expect(Prompt.system.contains(Prompt.assistantName))
        #expect(Prompt.system.contains("ground truth"))
        #expect(Prompt.system.contains("A persona is a tone, not a licence"))
    }
}

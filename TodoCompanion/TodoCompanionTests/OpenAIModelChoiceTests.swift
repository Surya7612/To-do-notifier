import Testing

@testable import TodoCompanion

@Suite("Which OpenAI model the picker shows")
struct OpenAIModelChoiceTests {
    @Test("a listed model selects itself rather than falling into Custom")
    func knownModelSelectsItself() {
        #expect(OpenAIModelChoice.selection(for: "gpt-5.6-terra") == .known("gpt-5.6-terra"))
    }

    @Test("a model newer than this build is reachable as Custom, not silently changed")
    func unknownModelBecomesCustom() {
        #expect(OpenAIModelChoice.selection(for: "gpt-6-something") == .custom)
    }

    /// The stored setting on an existing install. Without an entry it would
    /// show as "Custom…", which reads as though the user typed it.
    @Test("the legacy default is listed, so an existing setting appears as itself")
    func legacyDefaultIsListed() {
        #expect(OpenAIModelChoice.named(OpenAIBrain.defaultModel) != nil)
    }

    @Test("every listed model has a distinct API name")
    func namesAreUnique() {
        let names = OpenAIModelChoice.all.map(\.id)
        #expect(Set(names).count == names.count)
    }

    @Test("no listed model carries a price, which would go stale in the UI")
    func detailsQuoteNoPrices() {
        for choice in OpenAIModelChoice.all {
            #expect(!choice.detail.contains("$"), "\(choice.id) quotes a price")
        }
    }

    @Test("an empty or missing name is Custom rather than a crash")
    func emptyNameIsCustom() {
        #expect(OpenAIModelChoice.selection(for: "") == .custom)
        #expect(OpenAIModelChoice.named(nil) == nil)
    }
}

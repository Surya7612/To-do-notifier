import Foundation
import Testing
@testable import TodoCompanion

@MainActor
@Suite("What a failed answer says")
struct FailureMessageTests {
    @Test func transportErrorsAreRestatedInPlainWords() {
        let timedOut = CompanionViewModel.failureMessage(for: URLError(.timedOut))
        let dropped = CompanionViewModel.failureMessage(for: URLError(.networkConnectionLost))
        let offline = CompanionViewModel.failureMessage(for: URLError(.notConnectedToInternet))

        #expect(timedOut == BrainError.timedOut.localizedDescription)
        #expect(dropped == BrainError.connectionLost.localizedDescription)
        #expect(offline.contains("local model"))
        for message in [timedOut, dropped, offline] {
            #expect(!message.contains("NSURLErrorDomain"))
        }
    }

    @Test func aMissingModelNamesTheCommandThatFixesIt() {
        let message = BrainError.modelNotPulled("llama3.2").localizedDescription
        #expect(message.contains("ollama pull llama3.2"))
        #expect(!message.contains("404"))
    }

    @Test func otherErrorsPassThroughUnchanged() {
        let message = CompanionViewModel.failureMessage(for: BrainError.missingKey)
        #expect(message == BrainError.missingKey.localizedDescription)
    }
}

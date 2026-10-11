import Foundation
import Testing
@testable import TodoCompanion

@Suite("The task a reminder becomes")
struct ReminderTaskTitleTests {
    @Test func theCueAndADurationAreTakenOut() {
        #expect(ReminderPhrase.taskTitle(from: "Remind me in two hours to text voice bugs")
                == "Text voice bugs")
        #expect(ReminderPhrase.taskTitle(from: "remind me to send the email in 10 minutes")
                == "Send the email")
    }

    @Test func aStatedDayAndTimeAreTakenOut() {
        let title = ReminderPhrase.taskTitle(from: "Remind me to call the bank tomorrow at 5pm")
        #expect(title == "Call the bank")
    }

    @Test func aSentenceThatDoesNotAskIsLeftAlone() {
        // The time words here are what the note is about, not when to see it.
        let intent = "Notes from tomorrow's standup"
        #expect(ReminderPhrase.taskTitle(from: intent) == intent)
        #expect(ReminderPhrase.taskTitle(from: "Text voice bugs") == "Text voice bugs")
    }

    @Test func aSentenceThatIsAllCueKeepsItsWords() {
        // Nothing worth a title is left once "remind me tomorrow" loses both
        // halves, and the whole sentence says more than an empty row.
        #expect(ReminderPhrase.taskTitle(from: "Remind me tomorrow") == "Remind me tomorrow")
    }
}

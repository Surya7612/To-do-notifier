import Foundation
import SwiftData

@MainActor
enum ContextStore {
    /// Shared so the panel (AppKit-hosted) and the library window (a SwiftUI
    /// scene) read and write the same store.
    static let shared: ModelContainer = makeContainer()

    private static func makeContainer() -> ModelContainer {
        let schema = Schema([SavedContext.self, Project.self, ConversationTurn.self])
        do {
            return try ModelContainer(for: schema)
        } catch {
            // Better to run with a throwaway store than to refuse to launch.
            NSLog("[ContextStore] on-disk store unavailable, falling back to memory: \(error)")
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("[ContextStore] could not create any model container: \(error)")
            }
        }
    }
}

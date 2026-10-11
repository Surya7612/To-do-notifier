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
            let container = try ModelContainer(for: schema)
            logLibrarySize(in: container.mainContext)
            return container
        } catch {
            // Better to run with a throwaway store than to refuse to launch —
            // but this must never look like a silent wipe. Log loudly so a
            // signing / container mismatch (ad-hoc vs Development) is obvious.
            NSLog("[ContextStore] on-disk store unavailable, falling back to memory: \(error)")
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return try ModelContainer(for: schema, configurations: [config])
            } catch {
                fatalError("[ContextStore] could not create any model container: \(error)")
            }
        }
    }

    private static func logLibrarySize(in context: ModelContext) {
        let contexts = (try? context.fetchCount(FetchDescriptor<SavedContext>())) ?? -1
        let projects = (try? context.fetchCount(FetchDescriptor<Project>())) ?? -1
        NSLog("[ContextStore] library open — \(contexts) saved, \(projects) projects")
    }
}

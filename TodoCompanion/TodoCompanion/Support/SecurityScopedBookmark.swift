import Foundation

/// Resolves a security-scoped bookmark and refreshes it when the system says
/// the blob is stale.
///
/// Ignoring `bookmarkDataIsStale` leaves a link that looks configured while
/// every later read fails silently — the to-do bridge, phone inbox, and edit
/// file all hit that failure mode after the target moves.
enum SecurityScopedBookmark {
    /// Resolves `data`, rewriting the stored bookmark via `persist` when stale.
    /// Caller must still call `startAccessingSecurityScopedResource()`.
    static func resolve(_ data: Data, persist: (Data) -> Void) -> URL? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale)
        else { return nil }

        if stale {
            refresh(url, persist: persist)
        }
        return url
    }

    /// Creates a fresh bookmark while the caller already holds the scope.
    static func refresh(_ url: URL, persist: (Data) -> Void) {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        guard let fresh = try? url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
        else { return }
        persist(fresh)
    }
}

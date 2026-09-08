import AppKit
import Foundation
import SwiftData

/// One thing captured on a phone, waiting to be brought in.
struct InboxItem: Equatable, Sendable {
    /// The user's own reason, in their words. Same standing as the panel's
    /// intent field: authoritative, never inferred, never overwritten.
    let intent: String
    let imageData: Data?
    let createdAt: Date
    /// Where it came from, for provenance. Defaults to "iPhone" because that is
    /// what writes these, but it is the file's claim rather than ours.
    let source: String
}

/// Brings in things captured away from the Mac.
///
/// The transport is a folder the user picks, not iCloud. An iCloud container
/// needs an entitlement that requires the paid Apple Developer Program, which
/// this project does not have — but a *folder* inside iCloud Drive needs no
/// entitlement at all, and syncs just as well. So a Shortcut on the phone
/// writes a file there and this reads it, which also means the same mechanism
/// works with Dropbox, Syncthing, or a plain local folder.
///
/// Access goes through a security-scoped bookmark for the same reason
/// `TodoBridge` uses one: this app is sandboxed, and the user choosing the
/// folder is what grants it.
@MainActor
enum InboxImporter {
    private static let bookmarkKey = "inboxFolderBookmark"

    static var isLinked: Bool {
        UserDefaults.standard.data(forKey: bookmarkKey) != nil
    }

    /// Asks the user to choose the folder once.
    ///
    /// Read-write, because importing removes what it has imported — see
    /// `importAll`.
    static func link() -> Bool {
        let chosen = FilePicker.choose { panel in
            panel.title = "Choose your capture inbox"
            panel.message = "Pick the folder your iPhone Shortcut saves into. Anything it drops there will be brought in."
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.canCreateDirectories = true
            panel.allowsMultipleSelection = false
        }
        guard let url = chosen else { return false }

        do {
            let bookmark = try url.bookmarkData(options: .withSecurityScope,
                                                includingResourceValuesForKeys: nil,
                                                relativeTo: nil)
            UserDefaults.standard.set(bookmark, forKey: bookmarkKey)
            return true
        } catch {
            NSLog("[InboxImporter] couldn't bookmark \(url.path): \(error)")
            return false
        }
    }

    static func unlink() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
    }

    static var folderName: String? {
        withFolder { $0.lastPathComponent }
    }

    /// How many files are waiting. Cheap enough to call when opening Settings.
    static var pendingCount: Int {
        withFolder { folder in
            (try? FileManager.default.contentsOfDirectory(at: folder,
                                                          includingPropertiesForKeys: nil))
                .map { $0.filter { $0.pathExtension.lowercased() == "json" }.count } ?? 0
        } ?? 0
    }

    /// Reads everything waiting, saves it, and removes what it imported.
    ///
    /// - Returns: how many were brought in.
    ///
    /// Removal is the point rather than a side effect: the folder is a
    /// transport, not storage. The screenshot lives in this app's store once
    /// imported, and leaving the file behind would mean re-importing it on
    /// every launch forever. A file that *fails* to parse is deliberately left
    /// alone — deleting it would destroy something the user captured, and its
    /// staying put is the only signal that anything went wrong.
    @discardableResult
    static func importAll(into context: ModelContext, now: Date = Date()) -> Int {
        guard let imported = withFolder({ folder -> Int in
            let files = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []

            let manifests = files
                .filter { $0.pathExtension.lowercased() == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            var count = 0
            for manifest in manifests {
                guard let data = try? Data(contentsOf: manifest),
                      let item = parse(data, fallbackDate: now)
                else { continue }

                context.insert(makeRecord(from: item))
                try? FileManager.default.removeItem(at: manifest)
                count += 1
            }

            if count > 0 { try? context.save() }
            return count
        }) else { return 0 }

        return imported
    }

    static func makeRecord(from item: InboxItem) -> SavedContext {
        // Hashtags are split exactly as they are for a save typed at the Mac,
        // so `#engram` means the same thing whichever device it came from.
        let (intent, topics) = item.intent.splittingHashtags()

        let record = SavedContext(
            intent: intent,
            imageData: item.imageData,
            sourceApp: item.source,
            topics: topics
        )
        record.createdAt = item.createdAt
        return record
    }

    /// Parses one manifest.
    ///
    /// The image travels base64-encoded *inside* the JSON rather than as a
    /// second file. A pair of files sharing a name was the alternative and is
    /// worse over a syncing folder: the two halves arrive independently, so a
    /// reader can see a manifest whose image has not landed yet and cannot tell
    /// that from an image that is never coming.
    ///
    /// - Parameter fallbackDate: used when the file states no time, so an item
    ///   is never dated to 1970 and sorted to the bottom of the library.
    static func parse(_ data: Data, fallbackDate: Date = Date()) -> InboxItem? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let intent = (root["intent"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let imageData = (root["imageBase64"] as? String)
            .flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
            .flatMap { $0.isEmpty ? nil : $0 }

        // A reason with nothing attached is still worth keeping — a thought
        // captured on a walk is exactly what this is for. An image with no
        // reason is not: the reason is the thing this app is built around, and
        // inventing one would be inference posing as the user's words.
        guard !intent.isEmpty else { return nil }

        let stamps = ISO8601DateFormatter()
        stamps.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let createdAt = (root["createdAt"] as? String).flatMap {
            stamps.date(from: $0) ?? ISO8601DateFormatter().date(from: $0)
        }

        let source = (root["source"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        return InboxItem(
            intent: intent,
            imageData: imageData,
            createdAt: createdAt ?? fallbackDate,
            source: source.isEmpty ? "iPhone" : source
        )
    }

    /// Resolves the bookmark and holds the security scope for one operation.
    private static func withFolder<T>(_ work: (URL) -> T) -> T? {
        guard let bookmark = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }

        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark,
                                 options: .withSecurityScope,
                                 relativeTo: nil,
                                 bookmarkDataIsStale: &stale),
              url.startAccessingSecurityScopedResource()
        else { return nil }
        defer { url.stopAccessingSecurityScopedResource() }

        return work(url)
    }
}

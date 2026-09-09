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
    ///
    /// Counts placeholders too, so a manifest iCloud has named but not yet
    /// delivered still reads as waiting rather than as nothing there.
    static var pendingCount: Int {
        withFolder { folder in
            (try? FileManager.default.contentsOfDirectory(at: folder,
                                                          includingPropertiesForKeys: nil))
                .map { files in
                    files.filter { file in
                        let name = file.lastPathComponent.lowercased()
                        return file.pathExtension.lowercased() == "json" || name.hasSuffix(".json.icloud")
                    }.count
                } ?? 0
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
        guard let imported = withFolder({ folder -> [SavedContext] in
            let files = (try? FileManager.default.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.contentModificationDateKey]
            )) ?? []

            requestDownloads(for: files)

            let manifests = files
                .filter { $0.pathExtension.lowercased() == "json" }
                .filter(isReadable)
                .sorted { $0.lastPathComponent < $1.lastPathComponent }

            // Read the other app's settings only when there is something to
            // import. This runs on every summon, and the folder is empty almost
            // every time.
            guard !manifests.isEmpty else { return [] }
            let quietHours = TodoBridge.load().quietHours

            var records: [SavedContext] = []
            for manifest in manifests {
                guard let data = try? Data(contentsOf: manifest),
                      let item = parse(data, fallbackDate: now)
                else { continue }

                let record = makeRecord(from: item, quietHours: quietHours)
                context.insert(record)
                try? FileManager.default.removeItem(at: manifest)
                records.append(record)
            }

            if !records.isEmpty { try? context.save() }
            return records
        }) else { return 0 }

        schedule(for: imported, now: now)
        return imported.count
    }

    /// Asks iCloud for anything it has told us about but not yet handed over.
    ///
    /// A file in iCloud Drive can exist as a name with no contents behind it,
    /// and nothing downloads it until something asks. So the manifests this
    /// importer most needs — the ones that arrived while the Mac was asleep —
    /// are exactly the ones liable to be sitting there as placeholders, and
    /// without this call the folder stays visibly non-empty forever while the
    /// import does nothing, which reads as the feature being broken.
    ///
    /// A placeholder may also appear under a *different name*: the legacy form
    /// is `.thing.json.icloud`, which the `json` filter above does not match at
    /// all. Both shapes are asked for here rather than special-cased below.
    private static func requestDownloads(for files: [URL]) {
        for file in files {
            let name = file.lastPathComponent.lowercased()
            guard name.hasSuffix(".icloud") || (file.pathExtension.lowercased() == "json" && !isReadable(file))
            else { continue }

            try? FileManager.default.startDownloadingUbiquitousItem(at: file)
        }
    }

    /// Whether the bytes are actually on this disk.
    ///
    /// Checked rather than discovered by reading, because reading a placeholder
    /// blocks on the download — and this runs on the main actor, on every
    /// summon, so a slow network would freeze the panel as it opened. Anything
    /// not yet here is left for the next sweep, by which time the download this
    /// pass requested has usually landed.
    private static func isReadable(_ file: URL) -> Bool {
        let status = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            .ubiquitousItemDownloadingStatus

        // No status at all means it is not an iCloud item — a plain local
        // folder, or Dropbox — and those are readable by definition.
        guard let status else { return true }
        return status == .current || status == .downloaded
    }

    /// Arms the notifications behind whatever was just brought in.
    ///
    /// Only for a time still ahead of us. A past `remindAt` is kept on the
    /// record deliberately — it is what the user asked for, the library prints
    /// it as "already passed", and it still reaches the to-do app, which is the
    /// better place for something overdue. Scheduling it would achieve nothing
    /// silently, since a non-repeating calendar trigger whose date has gone by
    /// has no next matching date and never fires.
    private static func schedule(for records: [SavedContext], now: Date) {
        let due = records.compactMap { record -> (id: String, at: Date, intent: String, source: String)? in
            guard let remindAt = record.remindAt, remindAt > now else { return nil }
            return (record.reminderIdentifier, remindAt, record.intent, record.sourceApp)
        }
        guard !due.isEmpty else { return }

        Task {
            for reminder in due {
                _ = await Reminders.schedule(id: reminder.id,
                                             at: reminder.at,
                                             intent: reminder.intent,
                                             sourceApp: reminder.source)
            }
        }
    }

    static func makeRecord(from item: InboxItem,
                           quietHours: QuietHours = QuietHours()) -> SavedContext {
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
        record.remindAt = reminderDate(for: item, quietHours: quietHours)
        return record
    }

    /// The time an imported capture is asking to come back at, if it is asking.
    ///
    /// Held to exactly the bar a sentence typed at the Mac has to clear: an
    /// explicit cue *and* a time stated in the words themselves. "Remind me to
    /// eat the same in 12 hours" is carried out because both halves are the
    /// user's own; a date merely mentioned in passing is not, because at the Mac
    /// that is offered with the switch *off* and there is nobody here to turn it
    /// on. Which device a sentence was typed on is not a reason to read it
    /// differently — the two paths agreeing is the point.
    ///
    /// Resolved against `createdAt` rather than the moment of import, which is
    /// the difference that would otherwise be invisible: this Mac may have been
    /// asleep for hours when the file landed, and "in 12 hours" means twelve
    /// hours from when it was said, not from when it was noticed.
    static func reminderDate(for item: InboxItem,
                             quietHours: QuietHours,
                             calendar: Calendar = .current) -> Date? {
        guard let suggestion = ReminderPhrase.suggestion(in: item.intent,
                                                         now: item.createdAt,
                                                         calendar: calendar),
              suggestion.wasExplicitlyRequested,
              suggestion.matchedText != nil
        else { return nil }

        return quietHours.firstMomentAfter(suggestion.date, calendar: calendar)
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

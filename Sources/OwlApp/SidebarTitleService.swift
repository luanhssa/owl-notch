import Foundation

/// Reads what Claude Desktop already knows about a CLI session from its own
/// local records. Desktop persists one JSON file per Desktop-side
/// conversation at
/// `~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_<uuid>.json`,
/// each carrying the `cliSessionId` it's linked to, a `title` Desktop keeps
/// up to date, and its own internal id (the `local_<uuid>` filename stem). A
/// CLI session can have more than one linked record — e.g. duplicates left
/// over from `importCliSession` (see SessionFocusService) — so we pick the
/// non-archived one with the most recent `lastActivityAt`.
enum SidebarTitleService {
    private struct Entry {
        let title: String?
        let internalSessionID: String
        let lastActivityAt: Double
    }

    /// Guards `cache`/`lastScanAt`/`isScanning` — every current caller
    /// happens to run on the main actor, but that was only ever an
    /// unenforced convention (see GH issue #11), and the background scan
    /// this file now kicks off is by construction NOT on the main actor. A
    /// plain lock is enough here; there's no async work happening while
    /// held, just dictionary/Date reads and writes.
    private static let lock = NSLock()
    private static var cache: [String: Entry] = [:]
    private static var lastScanAt = Date.distantPast
    private static var isScanning = false
    /// Throttles re-scans so a burst of hook events (several tool calls in a
    /// row) doesn't re-read every session file on disk for each one.
    private static let scanInterval: TimeInterval = 2

    private static var sessionsRoot: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Claude/claude-code-sessions")
    }

    static func title(forCliSessionID cliSessionID: String) -> String? {
        kickOffRescanIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        guard let title = cache[cliSessionID]?.title, !title.isEmpty else { return nil }
        return title
    }

    /// Desktop's own id for the sidebar conversation already linked to this
    /// CLI session (the `local_<uuid>` filename stem, minus the prefix) —
    /// see SessionFocusService for why this is useful.
    static func internalSessionID(forCliSessionID cliSessionID: String) -> String? {
        kickOffRescanIfNeeded()
        lock.lock()
        defer { lock.unlock() }
        return cache[cliSessionID]?.internalSessionID
    }

    /// Serves whatever is already cached immediately, and — if the throttle
    /// window has elapsed and no scan is already in flight — kicks off the
    /// actual tree walk on a background queue instead of running it inline.
    /// Every caller into this file runs on the main actor (`SessionStore`,
    /// SwiftUI button actions), and the walk-and-parse in `scan()` can be
    /// slow with a large Claude Desktop history (GH issue #1); this trades
    /// "always current" for "never blocks," refreshing the cache
    /// asynchronously instead.
    private static func kickOffRescanIfNeeded() {
        lock.lock()
        let now = Date()
        guard !isScanning, now.timeIntervalSince(lastScanAt) >= scanInterval else {
            lock.unlock()
            return
        }
        isScanning = true
        lastScanAt = now
        lock.unlock()

        DispatchQueue.global(qos: .utility).async {
            let result = scan()
            lock.lock()
            cache = result
            isScanning = false
            lock.unlock()
        }
    }

    private static func scan() -> [String: Entry] {
        guard let enumerator = FileManager.default.enumerator(
            at: sessionsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [:] }

        var bestByCliID: [String: Entry] = [:]

        for case let url as URL in enumerator {
            let filename = url.deletingPathExtension().lastPathComponent
            guard url.pathExtension == "json", filename.hasPrefix("local_") else { continue }

            // Each guard below distinguishes a genuine parsing/schema
            // failure (worth logging — it means Claude Desktop's on-disk
            // format may have changed, GH issue #12) from the deliberate,
            // expected "isArchived" skip right after, which is not a
            // failure and must stay silent.
            guard let data = try? Data(contentsOf: url) else {
                NSLog("Owl: couldn't read Claude Desktop session record at \(url.path)")
                continue
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                NSLog("Owl: couldn't parse Claude Desktop session record as JSON at \(url.path)")
                continue
            }
            guard let cliSessionID = json["cliSessionId"] as? String else {
                NSLog("Owl: Claude Desktop session record at \(url.path) has no string cliSessionId — its format may have changed")
                continue
            }
            guard json["isArchived"] as? Bool != true else { continue }

            let lastActivityAt: Double
            if let value = json["lastActivityAt"] as? Double {
                lastActivityAt = value
            } else if json["lastActivityAt"] != nil {
                // Present but not a Double — a real format change, unlike a
                // freshly created record that just doesn't have this key yet.
                NSLog("Owl: Claude Desktop session record at \(url.path) has a non-numeric lastActivityAt — its format may have changed")
                lastActivityAt = 0
            } else {
                lastActivityAt = 0
            }

            let candidate = Entry(
                title: json["title"] as? String,
                internalSessionID: String(filename.dropFirst("local_".count)),
                lastActivityAt: lastActivityAt
            )
            if let existing = bestByCliID[cliSessionID], !isBetter(candidate, than: existing) {
                continue
            }
            bestByCliID[cliSessionID] = candidate
        }

        return bestByCliID
    }

    /// A titled record always beats an untitled one, regardless of recency —
    /// a fresh duplicate left behind by `importCliSession` (see
    /// SessionFocusService) has no title yet and, being freshly created, has
    /// the *most recent* `lastActivityAt` of the bunch. Breaking ties by
    /// recency alone would make every subsequent lookup prefer that junk
    /// duplicate over the real, established conversation. Only once neither
    /// or both candidates have a title does recency decide.
    private static func isBetter(_ candidate: Entry, than current: Entry) -> Bool {
        let candidateHasTitle = !(candidate.title ?? "").isEmpty
        let currentHasTitle = !(current.title ?? "").isEmpty
        if candidateHasTitle != currentHasTitle { return candidateHasTitle }
        return candidate.lastActivityAt > current.lastActivityAt
    }
}

import Foundation

/// Computes Claude Code token spend inside the current 5-hour usage window
/// by reading the same transcript JSONL files Claude Code itself writes to
/// `~/.claude/projects/<project>/<session>.jsonl` — one directory per
/// project, one file per session, one JSON line per turn. There is no API
/// for this; the transcripts are the only local record of token usage, the
/// same source tools like `ccusage` read.
///
/// Split in two per docs/PATTERNS.md #14: `scan(projectsRoot:now:)` is a
/// pure function taking its root directory and "now" explicitly, so tests
/// can point it at a fixture tree instead of the developer's real
/// `~/.claude/projects` — production code gets the exact same default it
/// always had. `TokenUsageStore` (a separate `ObservableObject`) owns the
/// timer/publishing side for SwiftUI; this file only computes.
enum TokenUsageService {
    /// Claude Code meters usage in rolling 5-hour windows, so that — not a
    /// calendar day or week — is the only period with a real ceiling to
    /// draw a progress bar against.
    static let windowDuration: TimeInterval = 5 * 60 * 60

    struct Snapshot: Equatable {
        static let zero = Snapshot(windowTokens: 0, windowStart: nil, weekTokens: 0, weekEnd: nil)

        /// Tokens spent so far inside the currently-open 5-hour window.
        var windowTokens: Int
        /// When the open window began, or `nil` when there is no open
        /// window — no transcripts at all, or the last one ended more than
        /// `windowDuration` ago. A `nil` start means "idle", which the UI
        /// renders as an empty bar rather than a full or missing one.
        var windowStart: Date?

        /// Tokens spent since the start of the current weekly window.
        ///
        /// Claude Code's own weekly limit resets on a per-account schedule
        /// that isn't recorded in the transcripts, so by default this is
        /// just the calendar week in the user's current locale — close
        /// enough to answer "how heavy has this week been", but not
        /// claiming to mirror the plan's exact reset instant. Setting
        /// `Preferences.weeklyResetWeekday`/`weeklyResetHour` (to whatever
        /// day/time Claude Code's own `/usage` panel reports) anchors this
        /// to that instant instead — see `weekInterval(weekResetWeekday:
        /// weekResetHour:now:)`.
        var weekTokens: Int
        /// Start of the *next* weekly window — i.e. when `weekTokens` rolls
        /// back to zero. `nil` only on the empty snapshot.
        var weekEnd: Date?

        var windowEnd: Date? {
            windowStart.map { $0.addingTimeInterval(windowDuration) }
        }
    }

    static var defaultProjectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    private struct Turn {
        /// Identifies one real API response so the same turn appearing in
        /// more than one line/file (a resumed or compacted session) is
        /// only counted once. Always present — see `dedupKey(...)` below
        /// for the fallback used when a line is missing the fields that
        /// would normally provide it.
        let dedupKey: String
        let timestamp: Date
        let tokens: Int
    }

    private struct CacheEntry {
        let mtime: Date
        let size: Int
        let turns: [Turn]
    }

    /// Per-file cache of parsed turns, keyed by path and invalidated by
    /// (mtime, size) — a file that hasn't changed since the last scan is
    /// never re-read or re-parsed. Without this, `scan` would re-read and
    /// re-parse the user's *entire* lifetime of transcripts on every call
    /// (`TokenUsageStore` calls it every 30s for as long as Owl runs) —
    /// cost that only grows with total history, even though a closed
    /// session's turns can never change once written (found during #49's
    /// review). Thread-safe the same way `GitInfoService`/
    /// `SessionTitleService` are, since this can be read from more than
    /// one background scan if a future caller doesn't serialize them.
    private static let lock = NSLock()
    private static var cache: [String: CacheEntry] = [:]
    /// Which `cache` keys each scanned root produced on its last scan —
    /// what eviction diffs against (GH issue #52). Guarded by `lock`.
    private static var pathsByRoot: [String: Set<String>] = [:]

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    // Claude Code has always written millisecond timestamps so far, but
    // fall back to the no-fractional-seconds variant rather than silently
    // dropping the line if that ever changes.
    private static let isoFormatterNoFraction = ISO8601DateFormatter()

    /// Scans every `.jsonl` transcript under `projectsRoot`, groups the
    /// assistant turns into 5-hour windows, and returns the one still open
    /// at `now`.
    static func scan(
        projectsRoot: URL = defaultProjectsRoot,
        weekResetWeekday: Int? = Preferences.weeklyResetWeekday(),
        weekResetHour: Int = Preferences.weeklyResetHour(),
        now: Date = Date()
    ) -> Snapshot {
        let turns = dedupe(collectTurns(projectsRoot: projectsRoot))
        return snapshot(fromTurns: turns, weekResetWeekday: weekResetWeekday, weekResetHour: weekResetHour, now: now)
    }

    private static func collectTurns(projectsRoot: URL) -> [Turn] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectsRoot,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var allTurns: [Turn] = []
        var seenPaths: Set<String> = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard
                let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                let mtime = resourceValues.contentModificationDate,
                let size = resourceValues.fileSize
            else { continue }

            let path = url.path
            seenPaths.insert(path)
            lock.lock()
            let cached = cache[path]
            lock.unlock()

            if let cached, cached.mtime == mtime, cached.size == size {
                allTurns.append(contentsOf: cached.turns)
                continue
            }

            let turns = parseTurns(fileURL: url)
            lock.lock()
            cache[path] = CacheEntry(mtime: mtime, size: size, turns: turns)
            lock.unlock()
            allTurns.append(contentsOf: turns)
        }

        // Drop entries for transcripts under this root that weren't seen
        // this scan (deleted or moved), so the cache tracks what's on disk
        // rather than every file ever seen since launch (GH issue #52).
        // Scoped per `projectsRoot` (via the paths that root produced last
        // time) because the cache is shared across roots — tests scan
        // their own temporary ones — and comparing enumerator paths
        // against a root-path prefix would be fragile under symlinked
        // locations like macOS's /var → /private/var.
        lock.lock()
        let previousPaths = pathsByRoot[projectsRoot.path] ?? []
        for path in previousPaths.subtracting(seenPaths) {
            cache[path] = nil
        }
        pathsByRoot[projectsRoot.path] = seenPaths
        lock.unlock()

        return allTurns
    }

    /// Test-only view into the per-file cache, so eviction (GH issue #52)
    /// can be asserted without exposing the cache itself.
    static func cachedPaths() -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(cache.keys)
    }

    /// How much of a transcript is read per `FileHandle` call. Reading in
    /// chunks keeps a scan's peak memory at about this size plus the
    /// longest single line, instead of the whole file — a long session
    /// with big embedded tool outputs can run to hundreds of MB (GH issue
    /// #51). Unlike `SessionTitleService.maxBytesRead`, this isn't a cap:
    /// every turn in the file has to be counted, so the whole file is
    /// still read, just never all at once.
    private static let readChunkSize = 1024 * 1024
    private static let newline = UInt8(ascii: "\n")

    private static func parseTurns(fileURL: URL) -> [Turn] {
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return [] }
        defer { try? handle.close() }

        var turns: [Turn] = []
        // Bytes of a line that started in an earlier chunk but hasn't hit
        // its newline yet.
        var pending = Data()
        // How far into `pending` is already known to hold no newline, so a
        // single line spanning many chunks isn't rescanned from its start
        // on every chunk.
        var searchFrom = 0
        while true {
            // Each chunk, and the JSON objects parsed from it, are
            // autoreleased; without a pool per chunk they'd pile up until
            // the whole file had been read, defeating the chunking.
            let reachedEnd: Bool = autoreleasepool {
                // `read(upToCount:)` throws on an I/O error, where
                // `readData(ofLength:)` would raise an uncatchable exception.
                guard let chunk = try? handle.read(upToCount: readChunkSize), !chunk.isEmpty else { return true }
                pending.append(chunk)

                var lineStart = pending.startIndex
                var searchStart = pending.startIndex + searchFrom
                while let lineEnd = pending[searchStart...].firstIndex(of: newline) {
                    if let turn = parseTurn(lineData: pending[lineStart..<lineEnd]) {
                        turns.append(turn)
                    }
                    lineStart = pending.index(after: lineEnd)
                    searchStart = lineStart
                }
                // Re-based copy so `pending`'s indices start at 0 again rather
                // than growing with every chunk.
                pending = Data(pending[lineStart...])
                searchFrom = pending.count
                return false
            }
            if reachedEnd { break }
        }
        // A last line with no trailing newline.
        if let turn = parseTurn(lineData: pending) {
            turns.append(turn)
        }
        return turns
    }

    private static func parseTurn(lineData: Data) -> Turn? {
        guard
            !lineData.isEmpty,
            let json = try? JSONSerialization.jsonObject(with: Data(lineData)) as? [String: Any],
            json["type"] as? String == "assistant",
            let message = json["message"] as? [String: Any],
            let usage = message["usage"] as? [String: Any]
        else { return nil }

        let tokens = tokenCount(fromUsage: usage)
        guard tokens > 0 else { return nil }

        guard
            let timestampString = json["timestamp"] as? String,
            let timestamp = isoFormatter.date(from: timestampString) ?? isoFormatterNoFraction.date(from: timestampString)
        else { return nil }

        let key = dedupKey(json: json, message: message, timestamp: timestamp, tokens: tokens)
        return Turn(dedupKey: key, timestamp: timestamp, tokens: tokens)
    }

    /// `message.id` + `requestId` together identify one real API response
    /// — mirrors the dedup key other local Claude Code usage tools (e.g.
    /// ccusage) use for the same reason. When either is missing (an
    /// older/newer transcript format, a malformed line), falls back step by
    /// step rather than skipping dedup entirely for exactly the atypical
    /// lines where duplication is most likely (found during #49's review):
    ///
    /// 1. Whichever of `message.id` / `requestId` is still there. Claude
    ///    Code writes one API response as several lines — one per content
    ///    block, each with its own `uuid` but repeating the response's full
    ///    `usage` — and every one of them shares both ids. So either id
    ///    alone still collapses them; nothing below does (measured on real
    ///    transcripts: keying by `uuid` or by the composite instead roughly
    ///    doubled the total, GH issue #53).
    /// 2. The line's own `uuid`. A resumed/compacted session that copies a
    ///    line into a new file keeps it, and two *different* turns never
    ///    share it, so unlike the composite it can't merge them — but it
    ///    can't collapse a response's per-block lines either.
    /// 3. A (timestamp, model, tokens) composite, only for a line with no
    ///    `uuid` either — two distinct turns landing on the same
    ///    second/model/total would collide, but it still catches an exact
    ///    repeat.
    ///
    /// Each step is prefixed so keys from different steps never collide.
    private static func dedupKey(json: [String: Any], message: [String: Any], timestamp: Date, tokens: Int) -> String {
        let messageID = nonEmptyString(message["id"])
        let requestID = nonEmptyString(json["requestId"])
        if let messageID, let requestID {
            return "\(messageID)|\(requestID)"
        }
        if let messageID {
            return "message|\(messageID)"
        }
        if let requestID {
            return "request|\(requestID)"
        }
        if let uuid = nonEmptyString(json["uuid"]) {
            return "uuid|\(uuid)"
        }
        let model = message["model"] as? String ?? ""
        return "fallback|\(timestamp.timeIntervalSince1970)|\(model)|\(tokens)"
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    /// Dedup has to run across the *combined* set of turns from every
    /// file, not per-file — a repeated turn can land in a different file
    /// than the original (a resumed or compacted session), and per-file
    /// caching above means each file's turns are parsed independently.
    private static func dedupe(_ turns: [Turn]) -> [Turn] {
        var seenKeys = Set<String>()
        return turns.filter { seenKeys.insert($0.dedupKey).inserted }
    }

    /// Replays the turns in chronological order to find the window that is
    /// still open at `now`. A window opens on the first turn after an idle
    /// gap, anchored to the top of that turn's hour — the same anchoring
    /// Claude Code's own usage reporting and `ccusage` use, so Owl's bar
    /// lines up with what the CLI tells you about your limits. It closes
    /// `windowDuration` later, or as soon as `windowDuration` passes with
    /// no turns at all.
    private static func snapshot(
        fromTurns turns: [Turn],
        weekResetWeekday: Int?,
        weekResetHour: Int,
        now: Date
    ) -> Snapshot {
        guard !turns.isEmpty else { return .zero }
        let sorted = turns.sorted { $0.timestamp < $1.timestamp }

        let weekInterval = weekInterval(weekResetWeekday: weekResetWeekday, weekResetHour: weekResetHour, now: now)
        let weekTokens = weekInterval.map { interval in
            sorted.filter { $0.timestamp >= interval.start }.reduce(0) { $0 + $1.tokens }
        } ?? 0

        var windowStart: Date?
        var windowTokens = 0
        var previousTimestamp: Date?

        for turn in sorted {
            let startsNewWindow = windowStart.map { start in
                turn.timestamp >= start.addingTimeInterval(windowDuration)
                    || previousTimestamp.map { turn.timestamp.timeIntervalSince($0) >= windowDuration } ?? false
            } ?? true

            if startsNewWindow {
                windowStart = floorToHour(turn.timestamp)
                windowTokens = 0
            }

            windowTokens += turn.tokens
            previousTimestamp = turn.timestamp
        }

        // The last window found is only the *current* one if it hasn't
        // already elapsed; otherwise the user is idle and the 5h bar is
        // empty — but the week's total still stands, so this returns a
        // snapshot with a nil window rather than `.zero`.
        let openWindowStart = windowStart.flatMap { start in
            now < start.addingTimeInterval(windowDuration) ? start : nil
        }
        return Snapshot(
            windowTokens: openWindowStart == nil ? 0 : windowTokens,
            windowStart: openWindowStart,
            weekTokens: weekTokens,
            weekEnd: weekInterval?.end
        )
    }

    /// The weekly window containing `now`: from `weekResetWeekday`/
    /// `weekResetHour` (local time) at or just before `now`, to the same
    /// instant seven days later. `weekResetWeekday == nil` (the default —
    /// no reset day configured in Preferences) falls back to the plain
    /// calendar week, matching Owl's original behavior before this was
    /// configurable.
    private static func weekInterval(weekResetWeekday: Int?, weekResetHour: Int, now: Date) -> DateInterval? {
        let calendar = Calendar.current
        guard let weekResetWeekday else {
            return calendar.dateInterval(of: .weekOfYear, for: now)
        }

        var components = DateComponents()
        components.weekday = weekResetWeekday
        components.hour = weekResetHour
        components.minute = 0
        components.second = 0

        guard
            let start = calendar.nextDate(
                after: now,
                matching: components,
                matchingPolicy: .nextTimePreservingSmallerComponents,
                direction: .backward
            ),
            let end = calendar.date(byAdding: .day, value: 7, to: start)
        else { return nil }

        return DateInterval(start: start, end: end)
    }

    private static func floorToHour(_ date: Date) -> Date {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        return calendar.date(from: components) ?? date
    }

    /// Sums every token bucket Claude Code reports for a turn — input,
    /// output, and both cache buckets — since all four represent tokens
    /// actually billed/consumed for that API call, not just newly-generated
    /// output.
    private static func tokenCount(fromUsage usage: [String: Any]) -> Int {
        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        return input + output + cacheCreation + cacheRead
    }
}

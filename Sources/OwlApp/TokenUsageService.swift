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

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard
                let resourceValues = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey]),
                let mtime = resourceValues.contentModificationDate,
                let size = resourceValues.fileSize
            else { continue }

            let path = url.path
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

        return allTurns
    }

    private static func parseTurns(fileURL: URL) -> [Turn] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [] }
        let text = String(decoding: data, as: UTF8.self)

        var turns: [Turn] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard
                let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                json["type"] as? String == "assistant",
                let message = json["message"] as? [String: Any],
                let usage = message["usage"] as? [String: Any]
            else { continue }

            let tokens = tokenCount(fromUsage: usage)
            guard tokens > 0 else { continue }

            guard
                let timestampString = json["timestamp"] as? String,
                let timestamp = isoFormatter.date(from: timestampString) ?? isoFormatterNoFraction.date(from: timestampString)
            else { continue }

            let key = dedupKey(json: json, message: message, timestamp: timestamp, tokens: tokens)
            turns.append(Turn(dedupKey: key, timestamp: timestamp, tokens: tokens))
        }
        return turns
    }

    /// `message.id` + `requestId` together identify one real API response
    /// — mirrors the dedup key other local Claude Code usage tools (e.g.
    /// ccusage) use for the same reason. When either is missing (an
    /// older/newer transcript format, a malformed line), falls back to a
    /// (timestamp, model, tokens) composite rather than skipping dedup
    /// entirely for exactly the atypical lines where duplication is most
    /// likely (found during #49's review) — narrower than the real key,
    /// but still catches an exact repeat.
    private static func dedupKey(json: [String: Any], message: [String: Any], timestamp: Date, tokens: Int) -> String {
        if let messageID = message["id"] as? String, let requestID = json["requestId"] as? String {
            return "\(messageID)|\(requestID)"
        }
        let model = message["model"] as? String ?? ""
        return "fallback|\(timestamp.timeIntervalSince1970)|\(model)|\(tokens)"
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

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
/// timer/caching/publishing side for SwiftUI; this file only computes.
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

        /// Tokens spent since the start of the current calendar week.
        ///
        /// Claude Code's own weekly limit resets on a per-account schedule
        /// that isn't recorded in the transcripts, so this is the calendar
        /// week in the user's current locale — close enough to answer "how
        /// heavy has this week been", but deliberately not claiming to
        /// mirror the plan's exact reset instant.
        var weekTokens: Int
        /// Start of the *next* calendar week — i.e. when `weekTokens`
        /// rolls back to zero. `nil` only on the empty snapshot.
        var weekEnd: Date?

        var windowEnd: Date? {
            windowStart.map { $0.addingTimeInterval(windowDuration) }
        }
    }

    static var defaultProjectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/projects", isDirectory: true)
    }

    private struct Turn {
        let timestamp: Date
        let tokens: Int
    }

    /// Scans every `.jsonl` transcript under `projectsRoot`, groups the
    /// assistant turns into 5-hour windows, and returns the one still open
    /// at `now`.
    static func scan(projectsRoot: URL = defaultProjectsRoot, now: Date = Date()) -> Snapshot {
        let turns = collectTurns(projectsRoot: projectsRoot)
        return snapshot(fromTurns: turns, now: now)
    }

    private static func collectTurns(projectsRoot: URL) -> [Turn] {
        guard let enumerator = FileManager.default.enumerator(
            at: projectsRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        // Claude Code has always written millisecond timestamps so far, but
        // fall back to the no-fractional-seconds variant rather than silently
        // dropping the line if that ever changes.
        let isoFormatterNoFraction = ISO8601DateFormatter()

        // Guards against double-counting: a resumed or compacted session can
        // carry the same assistant turn into more than one line/file over
        // its lifetime. `message.id` + `requestId` together identify one
        // real API response — mirrors the dedup key used by other local
        // Claude Code usage tools (e.g. ccusage) for the same reason.
        var seenKeys = Set<String>()
        var turns: [Turn] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let data = try? Data(contentsOf: url), !data.isEmpty else { continue }
            let text = String(decoding: data, as: UTF8.self)

            for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
                guard
                    let lineData = line.data(using: .utf8),
                    let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                    json["type"] as? String == "assistant",
                    let message = json["message"] as? [String: Any],
                    let usage = message["usage"] as? [String: Any]
                else { continue }

                if let messageID = message["id"] as? String, let requestID = json["requestId"] as? String {
                    guard seenKeys.insert("\(messageID)|\(requestID)").inserted else { continue }
                }

                let tokens = tokenCount(fromUsage: usage)
                guard tokens > 0 else { continue }

                guard
                    let timestampString = json["timestamp"] as? String,
                    let timestamp = isoFormatter.date(from: timestampString) ?? isoFormatterNoFraction.date(from: timestampString)
                else { continue }

                turns.append(Turn(timestamp: timestamp, tokens: tokens))
            }
        }

        return turns
    }

    /// Replays the turns in chronological order to find the window that is
    /// still open at `now`. A window opens on the first turn after an idle
    /// gap, anchored to the top of that turn's hour — the same anchoring
    /// Claude Code's own usage reporting and `ccusage` use, so Owl's bar
    /// lines up with what the CLI tells you about your limits. It closes
    /// `windowDuration` later, or as soon as `windowDuration` passes with
    /// no turns at all.
    private static func snapshot(fromTurns turns: [Turn], now: Date) -> Snapshot {
        guard !turns.isEmpty else { return .zero }
        let sorted = turns.sorted { $0.timestamp < $1.timestamp }

        let calendar = Calendar.current
        let weekInterval = calendar.dateInterval(of: .weekOfYear, for: now)
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

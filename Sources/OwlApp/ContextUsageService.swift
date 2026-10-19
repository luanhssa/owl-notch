import Foundation

/// How full a session's context window is, read from the last assistant
/// turn in its transcript (GH issue #42) — opt-in, off by default, gated
/// behind `Preferences.showContextUsage`.
///
/// Every assistant turn records the `usage` of the API call that produced
/// it, and that call's prompt (input + both cache buckets) plus the reply
/// it generated is what the *next* turn starts from — so the last turn's
/// total is the current context size. Same tail-read shape as
/// `LastMessageService`: only the end of the file matters, and the answer
/// changes every turn, so there's no cache.
enum ContextUsageService {
    struct Usage: Equatable {
        let tokens: Int
        let limit: Int

        /// 0...1, clamped — a turn can't really exceed its window, but a
        /// wrong `limit` guess shouldn't render a bar past 100%.
        var fraction: Double {
            guard limit > 0 else { return 0 }
            return min(1, Double(tokens) / Double(limit))
        }
    }

    /// Bounds worst-case I/O like `LastMessageService.maxBytesRead`; the
    /// last assistant turn is almost always within the final few KB, but a
    /// big tool result after it can push it further back.
    private static let maxBytesRead = 4 * 1024 * 1024
    private static let maxLinesScanned = 500

    /// The standard Claude context window. Transcripts don't record which
    /// window a session runs with (the `[1m]` model suffix isn't written
    /// to `message.model`), so this is inferred unless the user picked one
    /// — see `limit(for:)` and `Preferences.contextWindowLimit`.
    static let standardContextLimit = 200_000
    static let extendedContextLimit = 1_000_000

    /// `windowLimit` is the user's own pick from Preferences; `nil` means
    /// "Automático" and falls back to `limit(for:)`.
    static func usage(transcriptPath: String?, windowLimit: Int? = nil) -> Usage? {
        guard let transcriptPath else { return nil }
        guard let handle = FileHandle(forReadingAtPath: transcriptPath) else { return nil }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        let readSize = min(fileSize, UInt64(maxBytesRead))
        handle.seek(toFileOffset: fileSize - readSize)
        let data = handle.readData(ofLength: Int(readSize))
        guard !data.isEmpty else { return nil }
        // Lossy decode, same reasoning as `LastMessageService`: a cut line
        // at the start of the chunk just fails to parse and is skipped.
        let text = String(decoding: data, as: UTF8.self)

        var scanned = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard scanned < maxLinesScanned else { break }
            scanned += 1

            guard
                let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                json["type"] as? String == "assistant",
                // Subagent turns run in their own context window, not the
                // main session's.
                json["isSidechain"] as? Bool != true,
                let message = json["message"] as? [String: Any],
                let usage = message["usage"] as? [String: Any]
            else { continue }

            let tokens = contextTokens(fromUsage: usage)
            guard tokens > 0 else { continue }
            return Usage(tokens: tokens, limit: windowLimit ?? limit(for: tokens))
        }
        return nil
    }

    /// Assumes the standard 200k window unless the session is already past
    /// it, which can only happen on the 1M extended window. A 1M session
    /// still under 200k therefore reads as fuller than it is, which is why
    /// Preferences lets the user pin the window instead.
    static func limit(for tokens: Int) -> Int {
        tokens > standardContextLimit ? extendedContextLimit : standardContextLimit
    }

    /// "200k", "1M" — for window sizes in the notch and in Preferences,
    /// where "1000k" would read oddly.
    static func windowLabel(_ limit: Int) -> String {
        limit % 1_000_000 == 0 ? "\(limit / 1_000_000)M" : "\(limit / 1_000)k"
    }

    private static func contextTokens(fromUsage usage: [String: Any]) -> Int {
        let input = usage["input_tokens"] as? Int ?? 0
        let output = usage["output_tokens"] as? Int ?? 0
        let cacheCreation = usage["cache_creation_input_tokens"] as? Int ?? 0
        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        return input + output + cacheCreation + cacheRead
    }
}

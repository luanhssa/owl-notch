import Foundation

/// Reads the last real message/tool-result text from a session's
/// transcript — the opt-in, richer counterpart to `lastToolSummary`'s
/// terse one-line label (GH issue #45). Off by default, gated behind
/// `Preferences.showLastMessageContent`: this surfaces real conversation
/// content, potentially sensitive, in Owl's always-visible notch panel —
/// a different privacy posture than the terse summary, which is exactly
/// the trade-off the issue flagged before allowing any implementation.
///
/// Mirrors `SessionTitleService`'s general shape (read transcript JSONL,
/// decode each line, extract text), but reads from the *end* of the file
/// instead of the start — this needs the *last* qualifying line, not the
/// first, and unlike a session's title (fixed forever once found), the
/// answer here changes on every turn, so there's no cache to keep.
enum LastMessageService {
    private static let maxLength = 400
    private static let maxLinesScanned = 500
    /// Bounds worst-case I/O the same way `SessionTitleService` does —
    /// reads only the tail of the file, not the whole thing, regardless
    /// of how long the transcript has grown.
    private static let maxBytesRead = 4 * 1024 * 1024

    static func lastMessageText(transcriptPath: String?) -> String? {
        guard let transcriptPath else { return nil }
        guard let handle = FileHandle(forReadingAtPath: transcriptPath) else { return nil }
        defer { handle.closeFile() }

        let fileSize = handle.seekToEndOfFile()
        let readSize = min(fileSize, UInt64(maxBytesRead))
        handle.seek(toFileOffset: fileSize - readSize)
        let data = handle.readData(ofLength: Int(readSize))
        guard !data.isEmpty else { return nil }
        // Lossy decode: reading from a mid-file offset may cut a
        // multi-byte character (or a line) at the start of this chunk —
        // acceptable since we scan from the end and only need whichever
        // qualifying line comes last.
        let text = String(decoding: data, as: UTF8.self)

        var scanned = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).reversed() {
            guard scanned < maxLinesScanned else { break }
            scanned += 1

            guard
                let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                let type = json["type"] as? String,
                type == "assistant" || type == "user",
                let message = json["message"] as? [String: Any]
            else { continue }

            if let extracted = extractText(fromContent: message["content"]) {
                return truncate(extracted)
            }
        }
        return nil
    }

    private static func extractText(fromContent content: Any?) -> String? {
        if let plain = content as? String {
            return nonEmpty(plain)
        }
        if let blocks = content as? [[String: Any]] {
            for block in blocks where block["type"] as? String == "text" {
                if let text = block["text"] as? String, let trimmed = nonEmpty(text) {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func truncate(_ text: String) -> String {
        if text.count <= maxLength { return text }
        return "\(text.prefix(maxLength - 1))…"
    }
}

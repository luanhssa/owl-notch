import Foundation

/// Derives a short, human-readable title for a session by reading the first
/// real user-authored text out of its transcript JSONL — skipping harness
/// noise (queue-operation lines, task-notification strings, tool_result-only
/// turns) so the title reflects what the person actually asked for.
enum SessionTitleService {
    private static let maxLength = 60
    private static let maxLinesScanned = 200
    /// Bounds worst-case I/O regardless of transcript size — large embedded
    /// images/attachments in early turns can otherwise make a single line huge.
    private static let maxBytesRead = 4 * 1024 * 1024

    static func deriveTitle(transcriptPath: String?) -> String? {
        guard
            let transcriptPath,
            let handle = FileHandle(forReadingAtPath: transcriptPath)
        else { return nil }
        defer { handle.closeFile() }

        let data = handle.readData(ofLength: maxBytesRead)
        guard !data.isEmpty else { return nil }
        // Lossy decode: a truncated line at the read boundary may cut a
        // multi-byte character, which would fail exact UTF-8 decoding.
        let text = String(decoding: data, as: UTF8.self)

        var scanned = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard scanned < maxLinesScanned else { break }
            scanned += 1

            guard
                let lineData = line.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                json["type"] as? String == "user",
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
            return isRealUserText(plain) ? plain : nil
        }
        if let blocks = content as? [[String: Any]] {
            for block in blocks where block["type"] as? String == "text" {
                if let text = block["text"] as? String, isRealUserText(text) {
                    return text
                }
            }
        }
        return nil
    }

    /// Filters out harness-injected strings that aren't something a person typed.
    private static func isRealUserText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let noisyPrefixes = ["<task-notification>", "<system-reminder>", "<user-prompt-submit-hook>"]
        return !noisyPrefixes.contains { trimmed.hasPrefix($0) }
    }

    private static func truncate(_ text: String) -> String {
        let singleLine = text.split(separator: "\n").first.map(String.init) ?? text
        if singleLine.count <= maxLength { return singleLine }
        let cut = singleLine.prefix(maxLength - 1)
        return "\(cut)…"
    }
}

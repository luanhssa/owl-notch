import Foundation

/// Checks GitHub for a newer published release of Owl (GH issue #46,
/// phase 1) — only *notices* and links to it; installing stays manual.
/// Off by default behind `Preferences.checkForUpdates`, since it's the one
/// thing in Owl that talks to the network.
///
/// Uses the public, unauthenticated releases API: its 60 requests/hour
/// per-IP limit is far beyond a weekly check, and `/releases/latest`
/// already excludes drafts and prereleases.
enum UpdateCheckService {
    struct Release: Equatable {
        let version: String
        let pageURL: URL
    }

    static let latestReleaseURL = URL(string: "https://api.github.com/repos/luanhssa/owl-notch/releases/latest")!

    /// Weekly is plenty for a hobby project's release cadence, and keeps
    /// the check from being anything more than background noise.
    static let checkInterval: TimeInterval = 7 * 24 * 60 * 60
    /// Fail-open like everything else in Owl (PATTERNS.md #4): a slow or
    /// unreachable GitHub just means no update notice this time.
    private static let requestTimeout: TimeInterval = 10

    static func isCheckDue(lastCheck: Date?, now: Date = Date()) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= checkInterval
    }

    static func fetchLatestRelease() async -> Release? {
        var request = URLRequest(url: latestReleaseURL, timeoutInterval: requestTimeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Owl", forHTTPHeaderField: "User-Agent")
        guard
            let result = try? await URLSession.shared.data(for: request),
            (result.1 as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return parseRelease(data: result.0)
    }

    /// GitHub's response is foreign data, so parsed loosely rather than
    /// with a `Codable` struct (PATTERNS.md #6).
    static func parseRelease(data: Data) -> Release? {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tag = json["tag_name"] as? String,
            let page = json["html_url"] as? String,
            let pageURL = URL(string: page)
        else { return nil }
        return Release(version: normalized(tag), pageURL: pageURL)
    }

    /// Numeric, component-wise comparison ("0.10.0" > "0.9.0", which a
    /// plain string compare gets wrong). Missing components count as 0;
    /// anything non-numeric makes the comparison fail closed (no notice).
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard
            let lhs = components(of: candidate),
            let rhs = components(of: current)
        else { return false }
        for index in 0..<max(lhs.count, rhs.count) {
            let a = index < lhs.count ? lhs[index] : 0
            let b = index < rhs.count ? rhs[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func normalized(_ version: String) -> String {
        version.hasPrefix("v") ? String(version.dropFirst()) : version
    }

    private static func components(of version: String) -> [Int]? {
        let parts = normalized(version).split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, !parts.contains(where: { $0 == nil }) else { return nil }
        return parts.compactMap { $0 }
    }
}

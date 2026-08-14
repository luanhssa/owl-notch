import Foundation

/// The one shared accessor for `~/Library/Application Support` — every
/// target that talks to Owl's socket/log/session files needs this, and it
/// used to be independently copy-pasted as `fm.urls(for:
/// .applicationSupportDirectory, in: .userDomainMask)[0]` in five different
/// places across three targets (GH issue #15). `FileManager.urls(for:in:)`
/// returns `[URL]`, but for `.applicationSupportDirectory`/`.userDomainMask`
/// on macOS this is documented to always return exactly one URL — safe to
/// force-index, but only once, here, with that assumption written down.
public enum OwlPaths {
    public static var applicationSupportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    }
}

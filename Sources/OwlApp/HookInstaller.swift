import Foundation

/// Wires Owl's own hooks into `~/.claude/settings.json` — the one manual
/// step `Scripts/install.sh` explicitly leaves for by-hand editing (GH
/// issue #43). Every function here takes its file paths as parameters,
/// defaulting to the real ones, so tests can point them at a temp file
/// instead — this rewrites a file Claude Code itself depends on for every
/// session, so it's the one place in the codebase where getting the
/// testing seam right matters most (see `docs/PATTERNS.md` #14).
///
/// Deliberately never called without the user's explicit, in-the-moment
/// consent (see the confirmation alert in `App.swift`) — this is
/// "modifying persistent configuration," not a routine action.
enum HookInstaller {
    struct EventHook {
        let event: String    // Claude Code's hook event name, e.g. "Notification"
        let argument: String // owl-hook's own event-type argument, e.g. "notification"
    }

    /// Mirrors exactly what README.md documents as the manual hook wiring —
    /// this is the automated version of that same set, not a superset.
    static let events: [EventHook] = [
        EventHook(event: "Notification", argument: "notification"),
        EventHook(event: "Stop", argument: "stop"),
        EventHook(event: "UserPromptSubmit", argument: "userpromptsubmit"),
        EventHook(event: "PreToolUse", argument: "pretooluse"),
    ]

    static var defaultOwlHookPath: String {
        NSHomeDirectory() + "/.claude/owl/owl-hook"
    }

    static var defaultSettingsURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".claude/settings.json")
    }

    /// Whether owl-hook is at the stable path `Scripts/install.sh` puts it
    /// at. Installing hook commands that point at a binary that doesn't
    /// exist yet would just be silently broken, so callers should check
    /// this before ever offering to install hooks.
    static func isOwlHookInstalled(atPath path: String = defaultOwlHookPath) -> Bool {
        FileManager.default.isExecutableFile(atPath: path)
    }

    /// Whether every one of Owl's hook commands is already present.
    static func areHooksInstalled(
        settingsURL: URL = defaultSettingsURL,
        owlHookPath: String = defaultOwlHookPath
    ) -> Bool {
        guard let settings = readSettings(at: settingsURL) else { return false }
        return events.allSatisfy { hasHook(for: $0, owlHookPath: owlHookPath, in: settings) }
    }

    /// Adds whichever of Owl's hook commands aren't already present,
    /// leaving every other key and every other hook entry untouched.
    /// Returns whether the file was actually changed.
    ///
    /// Trade-off, disclosed to the user before this ever runs: written via
    /// `JSONSerialization`, which can't preserve the original file's exact
    /// formatting — keys come back out alphabetically sorted (`.sortedKeys`,
    /// chosen so re-running this produces byte-identical output instead of
    /// Swift's unordered-dictionary hash order changing on every write).
    /// Content is fully preserved either way; only formatting isn't.
    @discardableResult
    static func install(
        settingsURL: URL = defaultSettingsURL,
        owlHookPath: String = defaultOwlHookPath
    ) -> Bool {
        var settings = readSettings(at: settingsURL) ?? [:]
        var hooksSection = settings["hooks"] as? [String: Any] ?? [:]
        var changed = false

        for eventHook in events where !hasHook(for: eventHook, owlHookPath: owlHookPath, in: settings) {
            var groups = hooksSection[eventHook.event] as? [[String: Any]] ?? []
            groups.append([
                "hooks": [
                    ["type": "command", "command": command(for: eventHook, owlHookPath: owlHookPath)]
                ]
            ])
            hooksSection[eventHook.event] = groups
            changed = true
        }

        guard changed else { return false }

        settings["hooks"] = hooksSection
        return writeSettings(settings, to: settingsURL)
    }

    private static func command(for eventHook: EventHook, owlHookPath: String) -> String {
        "\(owlHookPath) \(eventHook.argument)"
    }

    private static func hasHook(for eventHook: EventHook, owlHookPath: String, in settings: [String: Any]) -> Bool {
        guard
            let hooksSection = settings["hooks"] as? [String: Any],
            let groups = hooksSection[eventHook.event] as? [[String: Any]]
        else { return false }

        let target = command(for: eventHook, owlHookPath: owlHookPath)
        return groups.contains { group in
            guard let hooks = group["hooks"] as? [[String: Any]] else { return false }
            return hooks.contains { ($0["command"] as? String) == target }
        }
    }

    private static func readSettings(at url: URL) -> [String: Any]? {
        guard
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private static func writeSettings(_ settings: [String: Any], to url: URL) -> Bool {
        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys]) else {
            NSLog("Owl: failed to encode \(url.path)")
            return false
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            NSLog("Owl: failed to write \(url.path): \(error)")
            return false
        }
    }
}

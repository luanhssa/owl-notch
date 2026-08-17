import Foundation

/// A minimal, permissive JSON value used for `tool_input`, whose shape varies
/// per tool (Bash has `command`, Edit has `file_path`, etc.) — we only ever
/// need to pick a couple of known keys back out for display.
indirect enum JSONValue {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(any: Any) {
        switch any {
        case let v as String: self = .string(v)
        case let v as NSNumber:
            if CFGetTypeID(v) == CFBooleanGetTypeID() {
                self = .bool(v.boolValue)
            } else {
                self = .number(v.doubleValue)
            }
        case let v as [String: Any]:
            self = .object(v.mapValues { JSONValue(any: $0) })
        case let v as [Any]:
            self = .array(v.map { JSONValue(any: $0) })
        default:
            self = .null
        }
    }

    subscript(key: String) -> JSONValue? {
        if case let .object(dict) = self { return dict[key] }
        return nil
    }
}

/// Mirrors the real payload Claude Code sends on a hook's stdin (captured live
/// from a PreToolUse/Bash event — see HookInput fields below). Every field
/// beyond `hook_event_name`/`session_id` is optional since the exact set
/// varies per event type and harness version.
struct HookInput {
    let hookEventName: String?
    let sessionID: String?
    let cwd: String?
    let transcriptPath: String?
    let toolName: String?
    let toolInput: JSONValue?
    let toolUseID: String?
    let promptID: String?
    let permissionMode: String?
    let message: String?

    init(json: [String: Any]) {
        hookEventName = json["hook_event_name"] as? String
        sessionID = json["session_id"] as? String
        cwd = json["cwd"] as? String
        transcriptPath = json["transcript_path"] as? String
        toolName = json["tool_name"] as? String
        toolUseID = json["tool_use_id"] as? String
        promptID = json["prompt_id"] as? String
        permissionMode = json["permission_mode"] as? String
        message = json["message"] as? String
        if let rawToolInput = json["tool_input"] as? [String: Any] {
            toolInput = JSONValue(any: rawToolInput)
        } else {
            toolInput = nil
        }
    }
}

/// The envelope owl-hook wraps around the raw hook payload before sending it
/// over the socket: {"event_type": "<pretooluse|notification|stop|...>", "hook_input": {...}}
struct HookEnvelope {
    let eventType: String
    let hookInput: HookInput
    let terminalApp: String?
    /// The pty device path (e.g. `/dev/ttys003`) owl-hook's controlling
    /// terminal was attached to when this event fired — lets Owl target
    /// the exact tab a session is running in, not just its app (GH issue #31).
    let terminalTTY: String?
    /// tmux's own pane id (e.g. `%12`) if owl-hook was running inside a
    /// tmux pane, read from the `TMUX_PANE` environment variable tmux sets
    /// on every process inside one (GH issue #41, phase 1 — resolving and
    /// targeting the specific pane is a separate, not-yet-implemented phase).
    let tmuxPane: String?
    let environment: String // "code" | "cli" | "unknown"

    init?(data: Data) {
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let eventType = json["event_type"] as? String
        else { return nil }
        self.eventType = eventType
        self.hookInput = HookInput(json: json["hook_input"] as? [String: Any] ?? [:])
        self.terminalApp = json["terminal_app"] as? String
        self.tmuxPane = json["tmux_pane"] as? String
        self.terminalTTY = json["tty"] as? String
        self.environment = json["environment"] as? String ?? "unknown"
    }
}

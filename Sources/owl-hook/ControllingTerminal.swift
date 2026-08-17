import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Best-effort detection of the pty device path (e.g. `/dev/ttys003`) this
/// process's controlling terminal is attached to — lets Owl later target
/// the exact terminal tab a session is running in, instead of only
/// bringing the whole app to front (GH issue #31).
///
/// Opens `/dev/tty` explicitly rather than checking stdin/stdout/stderr:
/// Claude Code pipes the hook JSON into this process's stdin, so stdin
/// isn't the terminal — but `/dev/tty` always refers to the calling
/// process's actual controlling terminal, independent of any redirection,
/// if it has one at all (it won't for a process with no controlling
/// terminal, in which case this returns nil).
enum ControllingTerminal {
    static func ttyPath() -> String? {
        let fd = open("/dev/tty", O_RDONLY)
        guard fd >= 0 else { return nil }
        defer { close(fd) }
        guard let cPath = ttyname(fd) else { return nil }
        return String(cString: cPath)
    }
}

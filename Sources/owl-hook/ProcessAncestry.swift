import Foundation
import OwlShared
#if canImport(Darwin)
import Darwin
#endif

/// Best-effort classification of where a Claude session is running, by
/// walking parent PIDs from owl-hook's own parent up toward PID 1 via
/// sysctl(KERN_PROC_PID) — no subprocess spawn (`ps`), so it stays cheap
/// enough to run on every hook invocation.
enum ProcessAncestry {
    struct Info {
        let environment: String // "code" | "cli" | "unknown"
        let terminalApp: String? // only meaningful when environment == "cli"
    }

    private static let terminalProcessNames = TerminalAppRegistry.processNames
    private static let claudeDesktopProcessNames: Set<String> = ["Claude"]

    static func classify() -> Info {
        classify(ancestorProcessNames: walkAncestorProcessNames())
    }

    /// The actual name-matching logic, separated from the live sysctl-based
    /// walk below so it can be unit tested with a plain array of names
    /// instead of mocking process introspection (GH issue #38). Trade-off,
    /// noted for anyone re-optimizing this later: the original inline
    /// version returned as soon as a match was found partway up the walk;
    /// this always walks the full bounded chain first. Both share the same
    /// hard cap (`hops < 40` in `walkAncestorProcessNames`), so this is at
    /// most the same small number of extra syscalls already budgeted for
    /// the no-match case — not a meaningful cost given owl-hook's own
    /// socket connect/poll dance dominates its runtime anyway.
    static func classify(ancestorProcessNames: [String]) -> Info {
        for name in ancestorProcessNames {
            if terminalProcessNames.contains(name) {
                return Info(environment: "cli", terminalApp: name)
            }
            if claudeDesktopProcessNames.contains(name) {
                return Info(environment: "code", terminalApp: nil)
            }
        }
        return Info(environment: "unknown", terminalApp: nil)
    }

    private static func walkAncestorProcessNames() -> [String] {
        var pid = getppid()
        var hops = 0
        var names: [String] = []
        while pid > 1 && hops < 40 {
            if let name = processName(pid: pid) {
                names.append(name)
            }
            guard let parent = parentPid(of: pid), parent != pid else { break }
            pid = parent
            hops += 1
        }
        return names
    }

    private static func parentPid(of pid: pid_t) -> pid_t? {
        guard let kp = kinfoProc(for: pid) else { return nil }
        return kp.kp_eproc.e_ppid
    }

    private static func processName(pid: pid_t) -> String? {
        guard let kp = kinfoProc(for: pid) else { return nil }
        var comm = kp.kp_proc.p_comm
        return withUnsafeBytes(of: &comm) { raw -> String? in
            let bytes = raw.bindMemory(to: UInt8.self)
            let nullIndex = bytes.firstIndex(of: 0) ?? bytes.count
            return String(decoding: bytes[..<nullIndex], as: UTF8.self)
        }
    }

    private static func kinfoProc(for pid: pid_t) -> kinfo_proc? {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var size = MemoryLayout<kinfo_proc>.stride
        var kp = kinfo_proc()
        let result = sysctl(&mib, u_int(mib.count), &kp, &size, nil, 0)
        guard result == 0, size > 0 else { return nil }
        return kp
    }
}

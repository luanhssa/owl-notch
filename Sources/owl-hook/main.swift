import Foundation
import OwlShared
#if canImport(Darwin)
import Darwin
#endif

// owl-hook <event-type>
// Reads the Claude Code hook JSON payload from stdin and forwards it to the
// Owl.app local IPC server as a fire-and-forget notification — owl-hook never
// blocks Claude Code and never influences a permission decision. Owl is an
// informant only: it shows what happened/is pending and links back to the
// session so a human can go decide (approve, deny, review, continue) there.
//
// If Owl isn't running or doesn't respond within a short timeout, this exits
// 0 immediately so Claude Code's normal behavior is never affected.

let eventType = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "unknown"
let connectTimeoutMs: Int32 = 250

func exitAllow() -> Never {
    exit(0)
}

// Capture ancestry as the very first thing this process does, before
// reading stdin or touching the socket at all. classify() walks parent
// PIDs starting from getppid() — if the hook-invoking parent has already
// exited by the time this runs, owl-hook will have been reparented to
// launchd and getppid() returns 1, misclassifying a real "cli"/"code"
// session as "unknown". Running this first minimizes that window instead
// of doing it after the whole connect/poll dance, which alone can take up
// to connectTimeoutMs (GH issue #14).
let ancestry = ProcessAncestry.classify()
let terminalTTY = ControllingTerminal.ttyPath()

let stdinData = FileHandle.standardInput.readDataToEndOfFile()

let socketPath = OwlPaths.applicationSupportDirectory
    .appendingPathComponent("Owl/owl.sock")
    .path

let fd = socket(AF_UNIX, SOCK_STREAM, 0)
guard fd >= 0 else { exitAllow() }

let originalFlags = fcntl(fd, F_GETFL, 0)
_ = fcntl(fd, F_SETFL, originalFlags | O_NONBLOCK)

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
_ = withUnsafeMutablePointer(to: &addr.sun_path) { rawPtr in
    rawPtr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: addr.sun_path)) { ptr in
        socketPath.withCString { cstr in
            strncpy(ptr, cstr, MemoryLayout.size(ofValue: addr.sun_path) - 1)
        }
    }
}
let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)

let connectResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
        connect(fd, sockaddrPtr, addrLen)
    }
}

if connectResult != 0 && errno != EINPROGRESS {
    close(fd)
    exitAllow()
}

// Wait for the connection to become writable (i.e. actually connected), bounded
// by connectTimeoutMs. This is the fail-open guard: an unreachable/missing Owl
// socket must not add more than ~250ms to a Claude Code tool call.
var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
let pollResult = poll(&pfd, 1, connectTimeoutMs)
guard pollResult > 0 else {
    close(fd)
    exitAllow()
}

var soError: Int32 = 0
var soErrorLen = socklen_t(MemoryLayout<Int32>.size)
getsockopt(fd, SOL_SOCKET, SO_ERROR, &soError, &soErrorLen)
guard soError == 0 else {
    close(fd)
    exitAllow()
}

// Back to blocking mode for the (small, fast) write.
_ = fcntl(fd, F_SETFL, originalFlags)

var hookInput: Any = NSNull()
if let parsed = try? JSONSerialization.jsonObject(with: stdinData) {
    hookInput = parsed
}

var envelope: [String: Any] = [
    "event_type": eventType,
    "hook_input": hookInput,
]

envelope["environment"] = ancestry.environment
if let terminalApp = ancestry.terminalApp {
    envelope["terminal_app"] = terminalApp
}
if let terminalTTY {
    envelope["tty"] = terminalTTY
}

guard let outData = try? JSONSerialization.data(withJSONObject: envelope) else {
    close(fd)
    exitAllow()
}

var outLine = outData
outLine.append(UInt8(ascii: "\n"))

outLine.withUnsafeBytes { ptr in
    _ = write(fd, ptr.baseAddress, ptr.count)
}

close(fd)
exit(0)

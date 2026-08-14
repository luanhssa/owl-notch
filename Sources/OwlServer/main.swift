import Foundation
import OwlShared
#if canImport(Darwin)
import Darwin
#endif

// Writing to a socket whose peer already closed its end raises SIGPIPE, which
// kills the process by default. owl-hook (M1) doesn't wait for our response,
// so this happens on essentially every request — ignore it and handle EPIPE
// via write()'s return value instead.
signal(SIGPIPE, SIG_IGN)

// MARK: - Paths

let fm = FileManager.default
let supportDir = OwlPaths.applicationSupportDirectory.appendingPathComponent("Owl")
try? fm.createDirectory(at: supportDir, withIntermediateDirectories: true)

let socketPath = supportDir.appendingPathComponent("owl.sock").path
let logPath = supportDir.appendingPathComponent("owl.log").path

// MARK: - Logging

let logQueue = DispatchQueue(label: "owl.log")

func log(_ message: String) {
    logQueue.async {
        let line = "[\(ISO8601DateFormatter().string(from: Date()))] \(message)\n"
        FileHandle.standardOutput.write(line.data(using: .utf8)!)
        if let data = line.data(using: .utf8) {
            if fm.fileExists(atPath: logPath), let handle = FileHandle(forWritingAtPath: logPath) {
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                fm.createFile(atPath: logPath, contents: data)
            }
        }
    }
}

// MARK: - Unix domain socket server (M1: logs every payload it receives, no session state yet)

// Remove a stale socket file from a previous run so bind() doesn't fail with EADDRINUSE.
unlink(socketPath)

let serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
guard serverFd >= 0 else {
    fatalError("socket() failed: \(errno)")
}

var addr = sockaddr_un()
addr.sun_family = sa_family_t(AF_UNIX)
_ = withUnsafeMutablePointer(to: &addr.sun_path) { rawPtr in
    rawPtr.withMemoryRebound(to: CChar.self, capacity: MemoryLayout.size(ofValue: addr.sun_path)) { ptr in
        socketPath.withCString { cstr in
            strncpy(ptr, cstr, MemoryLayout.size(ofValue: addr.sun_path) - 1)
        }
    }
}

let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
        bind(serverFd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
    }
}
guard bindResult == 0 else {
    fatalError("bind() failed: \(errno)")
}

guard listen(serverFd, 32) == 0 else {
    fatalError("listen() failed: \(errno)")
}

log("OwlServer listening on \(socketPath)")

// MARK: - Accept loop

while true {
    let clientFd = accept(serverFd, nil, nil)
    guard clientFd >= 0 else { continue }

    DispatchQueue.global().async {
        defer { close(clientFd) }

        var buffer = [UInt8](repeating: 0, count: 65536)
        let bytesRead = read(clientFd, &buffer, buffer.count)
        guard bytesRead > 0 else { return }

        let data = Data(buffer[0..<bytesRead])
        let text = String(data: data, encoding: .utf8) ?? "<invalid utf8: \(bytesRead) bytes>"
        log("received: \(text)")

        let response = "{\"status\":\"ok\"}\n"
        response.withCString { cstr in
            _ = write(clientFd, cstr, strlen(cstr))
        }
    }
}

import Foundation
import OwlShared
#if canImport(Darwin)
import Darwin
#endif

/// Unix domain socket server embedded in the Owl app process. Runs its
/// accept/read loop on a background thread (blocking socket calls are fine
/// there) and hands parsed events back to the SessionStore on the main actor.
/// Every event is fire-and-forget: Owl is an informant, never a gate — it
/// doesn't hold connections open waiting for a human decision.
final class IPCServer {
    private let store: SessionStore
    private var serverFd: Int32 = -1

    /// Guards `serverFd`/`stopped` — `stop()` can be called from the main
    /// thread while `acceptLoop` reads them on its own background thread.
    private let lifecycleLock = NSLock()
    private var stopped = false

    init(store: SessionStore) {
        self.store = store
    }

    func start() {
        signal(SIGPIPE, SIG_IGN)

        let fm = FileManager.default
        let supportDir = OwlPaths.applicationSupportDirectory.appendingPathComponent("Owl")
        try? fm.createDirectory(at: supportDir, withIntermediateDirectories: true)
        let socketPath = supportDir.appendingPathComponent("owl.sock").path

        unlink(socketPath)

        serverFd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard serverFd >= 0 else {
            NSLog("Owl: socket() failed: \(errno)")
            return
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let sunPathSize = MemoryLayout.size(ofValue: addr.sun_path)
        // strncpy below silently truncates anything over sunPathSize - 1
        // bytes (1 reserved for the null terminator) — check first instead
        // of letting bind() quietly succeed on a shorter, wrong path that
        // owl-hook's independently-constructed path would never match
        // (GH issue #16).
        guard socketPath.utf8.count < sunPathSize else {
            NSLog("Owl: socket path too long for sockaddr_un (\(socketPath.utf8.count) bytes, max \(sunPathSize - 1)): \(socketPath)")
            return
        }
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { rawPtr in
            rawPtr.withMemoryRebound(to: CChar.self, capacity: sunPathSize) { ptr in
                socketPath.withCString { cstr in
                    strncpy(ptr, cstr, sunPathSize - 1)
                }
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr -> Int32 in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverFd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            NSLog("Owl: bind() failed: \(errno)")
            return
        }

        guard listen(serverFd, 32) == 0 else {
            NSLog("Owl: listen() failed: \(errno)")
            return
        }

        NSLog("Owl: IPC server listening on \(socketPath)")

        let fdCopy = serverFd
        Thread.detachNewThread { [weak self] in
            self?.acceptLoop(serverFd: fdCopy)
        }
    }

    /// Closes the listening socket and signals `acceptLoop` to exit instead
    /// of retrying — closing the fd out from under a blocked `accept()` call
    /// makes it return immediately with an error, which is the loop's cue
    /// that this shutdown was intentional (see `acceptLoop`).
    func stop() {
        lifecycleLock.lock()
        guard !stopped else { lifecycleLock.unlock(); return }
        stopped = true
        let fd = serverFd
        serverFd = -1
        lifecycleLock.unlock()

        if fd >= 0 { close(fd) }
    }

    private func acceptLoop(serverFd: Int32) {
        var consecutiveFailures = 0
        while true {
            let clientFd = accept(serverFd, nil, nil)
            if clientFd >= 0 {
                consecutiveFailures = 0
                DispatchQueue.global().async { [weak self] in
                    self?.handleConnection(clientFd)
                }
                continue
            }

            let failureErrno = errno

            lifecycleLock.lock()
            let weStopped = stopped
            lifecycleLock.unlock()
            // stop() closed this fd itself — that's the intentional-shutdown
            // signal, not a real failure worth logging or retrying.
            if weStopped { break }

            consecutiveFailures += 1
            NSLog("Owl: accept() failed (errno \(failureErrno)), retry #\(consecutiveFailures)")
            // Exponential backoff capped at 1s — without this, a persistent
            // failure (e.g. too many open files) busy-spins a CPU core.
            let delaySeconds = min(pow(2, Double(consecutiveFailures)) * 0.01, 1.0)
            Thread.sleep(forTimeInterval: delaySeconds)
        }
    }

    /// A legitimate owl-hook client writes its whole payload immediately
    /// after connecting (see its own ~250ms connect budget) — this just
    /// needs to be generous enough not to cut off a slow write under load,
    /// while still bounding how long a stalled/malicious connection can
    /// park a `DispatchQueue.global()` worker thread (GH issue #7).
    private static let readTimeoutSeconds: Int = 2

    /// Generous ceiling for a single hook payload — guards against a
    /// client that never closes its write side from growing
    /// `readFullMessage`'s buffer unboundedly.
    private static let maxEnvelopeBytes = 1024 * 1024

    private func handleConnection(_ clientFd: Int32) {
        defer { close(clientFd) }

        var timeout = timeval(tv_sec: Self.readTimeoutSeconds, tv_usec: 0)
        setsockopt(clientFd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        guard let data = Self.readFullMessage(from: clientFd), !data.isEmpty else { return }
        guard let envelope = HookEnvelope(data: data) else { return }

        let response = "{\"status\":\"ok\"}\n"
        response.withCString { cstr in
            _ = write(clientFd, cstr, strlen(cstr))
        }

        Task { @MainActor in
            self.store.handle(envelope: envelope)
        }
    }

    /// Unix stream sockets have no built-in message framing, so a single
    /// `read()` isn't guaranteed to return a whole envelope (GH issue #8).
    /// owl-hook always writes its complete payload and then closes its side
    /// of the connection immediately (see its own `main.swift`), so reading
    /// until EOF — rather than assuming one `read()` call is the whole
    /// message — reassembles a fragmented payload correctly. The read
    /// timeout set in `handleConnection` still bounds how long this can
    /// take for a client that never closes.
    private static func readFullMessage(from fd: Int32) -> Data? {
        var accumulated = Data()
        var chunk = [UInt8](repeating: 0, count: 65536)

        while accumulated.count < maxEnvelopeBytes {
            let bytesRead = read(fd, &chunk, chunk.count)
            guard bytesRead > 0 else { break } // 0 = EOF (expected); negative = error/timeout
            accumulated.append(chunk, count: bytesRead)
        }
        return accumulated
    }
}

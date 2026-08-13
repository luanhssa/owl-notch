import Foundation
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

    init(store: SessionStore) {
        self.store = store
    }

    func start() {
        signal(SIGPIPE, SIG_IGN)

        let fm = FileManager.default
        let supportDir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Owl")
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

    private func acceptLoop(serverFd: Int32) {
        while true {
            let clientFd = accept(serverFd, nil, nil)
            guard clientFd >= 0 else { continue }

            DispatchQueue.global().async { [weak self] in
                self?.handleConnection(clientFd)
            }
        }
    }

    private func handleConnection(_ clientFd: Int32) {
        defer { close(clientFd) }

        var buffer = [UInt8](repeating: 0, count: 65536)
        let bytesRead = read(clientFd, &buffer, buffer.count)
        guard bytesRead > 0 else { return }

        let data = Data(buffer[0..<bytesRead])
        guard let envelope = HookEnvelope(data: data) else { return }

        let response = "{\"status\":\"ok\"}\n"
        response.withCString { cstr in
            _ = write(clientFd, cstr, strlen(cstr))
        }

        Task { @MainActor in
            self.store.handle(envelope: envelope)
        }
    }
}

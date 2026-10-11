import Foundation
import Darwin
import CmuxRemoteCore

/// A kernel file lease prevents two processes from owning one registry/admin socket.
public final class BridgeRunLease: Sendable {
    private let descriptor: Int32
    public init(directory: URL) throws {
        let path = directory.appendingPathComponent("serve.lock").path
        let fd = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw BridgeError("state_unavailable", "The private Bridge state cannot be opened.") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else { Darwin.close(fd); throw BridgeError("already_running", "A Bridge already owns this state directory.") }
        var retained = false
        defer { if !retained { Darwin.close(fd) } }
        let socket = directory.appendingPathComponent("owner.sock")
        if FileManager.default.fileExists(atPath: socket.path) {
            let attrs = try FileManager.default.attributesOfItem(atPath: socket.path)
            guard attrs[.type] as? FileAttributeType == .typeSocket, (attrs[.ownerAccountID] as? NSNumber)?.uint32Value == geteuid() else { throw BridgeError("state_unavailable", "The owner socket path contains an unexpected file.") }
            try FileManager.default.removeItem(at: socket)
        }
        descriptor = fd; retained = true
    }
    deinit { Darwin.close(descriptor) }
}

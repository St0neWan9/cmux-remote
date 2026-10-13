import Foundation
import Darwin
import CmuxRemoteCore

/// One Bridge per Mac user, whatever its state directory, so each Mac presents exactly one host identity.
public final class BridgeMachineLease: Sendable {
    private let descriptor: Int32
    public init(home: URL) throws {
        let directory = home.appendingPathComponent(".local/state")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let fd = Darwin.open(directory.appendingPathComponent("cmux-remote-bridge.lock").path, O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw BridgeError("state_unavailable", "The Bridge machine lock cannot be opened.") }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw BridgeError("bridge_already_running", "Another Bridge is already running on this Mac. Stop it before starting a new one.")
        }
        descriptor = fd
    }
    deinit { Darwin.close(descriptor) }
}

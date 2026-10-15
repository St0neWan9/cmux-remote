import Darwin
import Foundation
import CmuxRemoteCore

/// A loopback TCP port that completes the TCP handshake in its backlog but never accepts or answers,
/// so a TLS or WebSocket dial to it hangs until its own deadline, like a LAN address that went quiet.
final class SilentTCPListener: @unchecked Sendable {
    let port: Int
    private let lock = NSLock()
    private var descriptor: Int32
    init() throws {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw BridgeError("fixture", "Socket creation failed") }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size); address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1"); address.sin_port = 0
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bound == 0, listen(descriptor, 8) == 0 else { Darwin.close(descriptor); throw BridgeError("fixture", "Socket bind failed") }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) }
        }
        guard named == 0 else { Darwin.close(descriptor); throw BridgeError("fixture", "Socket name failed") }
        self.descriptor = descriptor
        port = Int(UInt16(bigEndian: address.sin_port))
    }
    func close() { lock.withLock { if descriptor >= 0 { Darwin.close(descriptor); descriptor = -1 } } }
    deinit { close() }
}

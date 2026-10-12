import Darwin
import Foundation
import CmuxRemoteCore

/// One real Unix socket that closes or replies after consuming exactly one RPC.
struct SocketResponseFixture: Sendable {
    let completion: Task<Data, any Error>
    init(path: String, response: Data?) throws {
        let descriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw BridgeError("fixture", "Socket creation failed") }
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8) + [0]
        guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else { Darwin.close(descriptor); throw BridgeError("fixture", "Path too long") }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(descriptor, 1) == 0 else { Darwin.close(descriptor); throw BridgeError("fixture", "Socket bind failed") }
        completion = Task.detached {
            defer { Darwin.close(descriptor) }
            var ready = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
            guard Darwin.poll(&ready, 1, 2000) > 0 else { throw BridgeError("fixture", "No client connected") }
            let client = accept(descriptor, nil, nil)
            guard client >= 0 else { throw BridgeError("fixture", "Accept failed") }
            defer { Darwin.close(client) }
            var timeout = timeval(tv_sec: 2, tv_usec: 0)
            _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var request = Data(), buffer = [UInt8](repeating: 0, count: 4096)
            while !request.contains(10), request.count < 8192 {
                let count = Darwin.read(client, &buffer, buffer.count)
                guard count > 0 else { throw BridgeError("fixture", "RPC did not arrive") }
                request.append(contentsOf: buffer.prefix(count))
            }
            if let response {
                let count = response.withUnsafeBytes { Darwin.write(client, $0.baseAddress, $0.count) }
                guard count == response.count else { throw BridgeError("fixture", "Reply failed") }
            }
            return request
        }
    }
}

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
        let responseStream = AsyncThrowingStream<Data, any Error>.makeStream(bufferingPolicy: .bufferingNewest(1))
        // Enqueue blocking fixture IO before the cooperative client starts waiting.
        DispatchQueue.global(qos: .userInitiated).async {
            defer { Darwin.close(descriptor) }
            do {
                var ready = pollfd(fd: descriptor, events: Int16(POLLIN), revents: 0)
                let clock = ContinuousClock(), deadline = ContinuousClock().now + .seconds(2)
                while true {
                    let remaining = deadline - clock.now
                    guard remaining > .zero else { throw BridgeError("fixture", "No client connected") }
                    let parts = remaining.components
                    let milliseconds = Int32(max(1, min(2000, parts.seconds * 1000 + parts.attoseconds / 1_000_000_000_000_000)))
                    let result = Darwin.poll(&ready, 1, milliseconds)
                    if result > 0 { break }
                    if result < 0 && errno != EINTR { throw BridgeError("fixture", "Socket readiness failed") }
                }
                let client = accept(descriptor, nil, nil)
                guard client >= 0 else { throw BridgeError("fixture", "Accept failed") }
                defer { Darwin.close(client) }
                var timeout = timeval(tv_sec: 2, tv_usec: 0)
                _ = setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                var request = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                while !request.contains(10), request.count < 8192 {
                    let count = Darwin.read(client, &buffer, buffer.count)
                    if count < 0 && errno == EINTR { continue }
                    guard count > 0 else { throw BridgeError("fixture", "RPC did not arrive") }
                    request.append(contentsOf: buffer.prefix(count))
                }
                if let response {
                    let count = response.withUnsafeBytes { Darwin.write(client, $0.baseAddress, $0.count) }
                    guard count == response.count else { throw BridgeError("fixture", "Reply failed") }
                }
                responseStream.continuation.yield(request); responseStream.continuation.finish()
            } catch { responseStream.continuation.finish(throwing: error) }
        }
        completion = Task {
            var iterator = responseStream.stream.makeAsyncIterator()
            guard let bytes = try await iterator.next() else { throw BridgeError("fixture", "Fixture ended without a request") }
            return bytes
        }
    }
}

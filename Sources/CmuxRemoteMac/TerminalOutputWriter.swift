import Foundation
import Darwin
import CmuxRemoteCore

/// Writes complete frames despite shared tty nonblocking flags and output backpressure.
struct TerminalOutputWriter: Sendable {
    let descriptor: Int32
    var timeout: Duration = .seconds(5)
    func write(_ data: Data) throws {
        let clock = ContinuousClock(), deadline = ContinuousClock().now + timeout
        try data.withUnsafeBytes { bytes in
            var position = 0
            while position < bytes.count {
                try Task.checkCancellation()
                guard clock.now < deadline else { throw BridgeError("terminal_unavailable", "The local viewer output closed.") }
                let count = Darwin.write(descriptor, bytes.baseAddress!.advanced(by: position), bytes.count - position)
                if count > 0 { position += count; continue }
                if count < 0 && errno == EINTR { continue }
                if count < 0 && (errno == EAGAIN || errno == EWOULDBLOCK) {
                    // POSIX readiness has no async-native tty seam; waits are bounded and cancellation is rechecked.
                    var ready = pollfd(fd: descriptor, events: Int16(POLLOUT), revents: 0)
                    let result = Darwin.poll(&ready, 1, 100)
                    if result < 0 && errno == EINTR { continue }
                    guard result >= 0, ready.revents & Int16(POLLERR | POLLHUP | POLLNVAL) == 0 else {
                        throw BridgeError("terminal_unavailable", "The local viewer output closed.")
                    }
                    continue
                }
                throw BridgeError("terminal_unavailable", "The local viewer output closed.")
            }
        }
    }
}

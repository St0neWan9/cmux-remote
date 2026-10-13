import Foundation
import CmuxRemoteCore

/// Owns a Foundation WebSocket and its TLS session for exactly one network path.
final class LinkSocket: Sendable {
    let task: URLSessionWebSocketTask
    private let session: URLSession
    /// LAN sockets fail fast so the relay is tried promptly; relay sockets allow slow mobile and cross-border TLS.
    init(url: URL, delegate: (any URLSessionDelegate)? = nil, headers: [String: String] = [:], timeout: TimeInterval = 4) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = timeout; configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: delegate ?? RelaySessionDelegate(), delegateQueue: nil)
        var request = URLRequest(url: url); request.setValue("cmux-remote.v3", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        task = session.webSocketTask(with: request); task.maximumMessageSize = 2_100_000; task.resume()
    }
    func send(_ data: Data) async throws { try await task.send(.data(data)) }
    func receive() async throws -> Data {
        guard case .data(let data) = try await task.receive(), data.count <= 2_100_000 else { throw BridgeError("invalid_response", "Invalid WebSocket packet.", status: 502) }
        return data
    }
    func ping() async throws {
        try await withCheckedThrowingContinuation { (done: CheckedContinuation<Void, any Error>) in
            task.sendPing { error in if let error { done.resume(throwing: error) } else { done.resume() } }
        }
    }
    func close() { task.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
    deinit { task.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
}

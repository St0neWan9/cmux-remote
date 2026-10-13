import Foundation
import CmuxRemoteCore

/// Outgoing cloud WSS uses system PKI; the inner link authenticates Bridge separately.
public final class CloudRelaySocket: CloudRelayConnecting {
    private let session: URLSession
    private let task: URLSessionWebSocketTask
    public init(url: URL, headers: [String: String], delegate: (any URLSessionDelegate)? = nil) {
        let configuration = URLSessionConfiguration.ephemeral; configuration.timeoutIntervalForRequest = 10; configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration, delegate: delegate ?? CloudRelaySessionDelegate(), delegateQueue: nil)
        var request = URLRequest(url: url); request.setValue("cmux-remote.v3", forHTTPHeaderField: "Sec-WebSocket-Protocol")
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        task = session.webSocketTask(with: request); task.maximumMessageSize = 3_000_000; task.resume()
    }
    public func send(_ bytes: Data) async throws { try await task.send(.string(String(decoding: bytes, as: UTF8.self))) }
    public func receive() async throws -> Data {
        guard case .string(let text) = try await task.receive(), text.utf8.count <= 3_000_000 else { throw BridgeError("invalid_response", "Invalid relay envelope.", status: 502) }
        return Data(text.utf8)
    }
    public func ping() async throws {
        let ping = WebSocketPing()
        // Closing the session or cancelling the task can settle the ping twice; the helper keeps the first outcome.
        return try await withTaskCancellationHandler {
            try await ping.run { task.sendPing(pongReceiveHandler: $0) }
        } onCancel: { ping.cancel() }
    }
    public func failureCode() -> String {
        let status = (task.response as? HTTPURLResponse)?.statusCode
        return status == 401 || status == 403 ? "relay_configuration" : "connection_failed"
    }
    public func close() { task.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
    deinit { task.cancel(with: .goingAway, reason: nil); session.invalidateAndCancel() }
}

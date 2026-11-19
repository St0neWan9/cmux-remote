import Foundation
import NIOCore
import NIOPosix
import NIOHTTP1
import NIOWebSocket
@preconcurrency import NIOSSL
import CmuxRemoteCore

/// One `rex.control.v1` connection. It negotiates the API once, keeps one
/// client identity, and reconnects on the next request after a close. Events
/// are consumed but not persisted; inventory is read on demand.
public actor RexControlClient {
    public struct Welcome: Sendable, Equatable {
        public let clientID: String
        public let reconnectToken: String?
        public let apiRevision: Int
        public let apiServerRevision: Int
        public let maxMessageBytes: Int
    }

    private struct Pending {
        let continuation: CheckedContinuation<JSONValue, any Error>
        let timeout: Task<Void, Never>
    }

    private let endpoint: RexEndpoint
    private let group: EventLoopGroup
    private var channel: Channel?
    private var welcome: Welcome?
    private var connecting: Task<Welcome, any Error>?
    private var welcomeWaiter: CheckedContinuation<Welcome, any Error>?
    private var upgradeSignal: RexUpgradeSignal?
    private var pending: [String: Pending] = [:]
    private var nextID = 1
    private var closed = false

    public init(endpoint: RexEndpoint) {
        self.endpoint = endpoint
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    public func connect() async throws -> Welcome {
        if let welcome, let channel, channel.isActive { return welcome }
        if let connecting { return try await connecting.value }
        let task = Task { try await self.open() }
        connecting = task
        do {
            let value = try await task.value
            connecting = nil
            return value
        } catch {
            connecting = nil
            throw error
        }
    }

    public func request(_ method: String, _ payload: [String: JSONValue] = [:],
                        timeout: Duration = .seconds(10)) async throws -> JSONValue {
        _ = try await connect()
        return try await sendRequest(method, payload, timeout: timeout)
    }

    /// A request on an already negotiated connection. The handshake uses this
    /// directly so its attach call cannot wait on the connection it is opening.
    private func sendRequest(_ method: String, _ payload: [String: JSONValue],
                             timeout: Duration) async throws -> JSONValue {
        guard let channel, channel.isActive else {
            throw BridgeError("rex_unavailable", "The Rex server is not connected.", status: 503)
        }
        let id = "request-\(nextID)"; nextID += 1
        var object: [String: JSONValue] = ["type": .string("request"), "id": .string(id), "method": .string(method)]
        if !payload.isEmpty { object["payload"] = .object(payload) }
        let data = try JSONEncoder().encode(JSONValue.object(object))
        let limit = min(welcome?.maxMessageBytes ?? 1_048_576, 1_048_576)
        guard data.count <= limit else { throw BridgeError("rex_too_large", "The Rex request exceeds its limit.", status: 413) }
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task { [weak self] in
                try? await Task.sleep(for: timeout)
                guard !Task.isCancelled else { return }
                await self?.fail(id: id, error: BridgeError("rex_timeout", "The Rex request timed out.", status: 504))
            }
            pending[id] = Pending(continuation: continuation, timeout: timeoutTask)
            Task {
                do { try await self.writeText(data, on: channel) }
                catch { self.fail(id: id, error: error) }
            }
        }
    }

    public func close() async {
        closed = true
        let channel = self.channel
        self.channel = nil; self.welcome = nil
        if let channel { try? await channel.close().get() }
        for id in Array(pending.keys) { fail(id: id, error: BridgeError("rex_unavailable", "The Rex connection closed.", status: 503)) }
        welcomeWaiter?.resume(throwing: BridgeError("rex_unavailable", "The Rex connection closed.", status: 503))
        welcomeWaiter = nil
        try? await group.shutdownGracefully()
    }

    private func open() async throws -> Welcome {
        guard !closed else { throw BridgeError("rex_unavailable", "The Rex client is closed.", status: 503) }
        if let welcome, let channel, channel.isActive { return welcome }
        let (channel, signal) = try await openChannel()
        self.channel = channel
        self.upgradeSignal = signal
        do { try await signal.wait(timeout: .seconds(5)) }
        catch {
            upgradeSignal = nil
            try? await channel.close().get()
            throw error
        }
        upgradeSignal = nil
        let hello: JSONValue = .object([
            "type": .string("hello"),
            "api_revision": .number(16),
            "api_min_revision": .number(0),
            "client": .object(["kind": .string("other"), "platform": .string("macos"),
                               "name": .string("term-remote"), "version": .string("0.1.0")])
        ])
        let data = try JSONEncoder().encode(hello)
        try await writeText(data, on: channel)
        let value = try await withCheckedThrowingContinuation { continuation in
            welcomeWaiter = continuation
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                await self?.failWelcome(BridgeError("rex_handshake", "The Rex server did not answer the handshake.", status: 504))
            }
        }
        guard value.apiServerRevision >= 16 else {
            self.welcome = nil
            throw BridgeError("rex_update_required", "Update Rex to a server with API revision 16.", status: 422)
        }
        welcome = value
        _ = try? await sendRequest("session.attach_all", ["event_scope": .string("session")], timeout: .seconds(10))
        return value
    }

    private func openChannel() async throws -> (Channel, RexUpgradeSignal) {
        let client = self
        let signal = RexUpgradeSignal()
        let http = RexHTTPRequestHandler(host: endpoint.hostHeader, subprotocol: "rex.control.v1")
        let ws = RexWebSocketHandler(onText: { text in
            Task { await client.receive(text) }
        }, onClose: { code, reason in
            Task { await client.connectionClosed(code: code, reason: reason) }
        })
        let upgrader = NIOWebSocketClientUpgrader(maxFrameSize: 1 << 20) { channel, head in
            let protocolHeader = head.headers["Sec-WebSocket-Protocol"].joined(separator: ",")
            guard protocolHeader.contains("rex.control.v1") else {
                let error = BridgeError("rex_protocol", "The Rex server refused the control protocol.", status: 502)
                signal.fail(error)
                return channel.eventLoop.makeFailedFuture(error)
            }
            let added = channel.pipeline.addHandler(ws)
            added.whenComplete { result in
                switch result {
                case .success: signal.succeed()
                case .failure(let error): signal.fail(error)
                }
            }
            return added
        }
        let configuration: NIOHTTPClientUpgradeSendableConfiguration = (
            upgraders: [upgrader],
            completionHandler: { context in
                context.pipeline.syncOperations.removeHandler(http, promise: nil)
            }
        )
        let endpoint = self.endpoint
        let bootstrap = ClientBootstrap(group: group)
            .connectTimeout(.seconds(10))
            .channelInitializer { channel in
                do {
                    let upgrade: EventLoopFuture<Void>
                    if case .tcp(let host, _, true) = endpoint {
                        let tls = try RexTLSHandler(host: host)
                        upgrade = channel.pipeline.addHandler(tls.handler)
                    } else {
                        upgrade = channel.eventLoop.makeSucceededVoidFuture()
                    }
                    return upgrade.flatMap {
                        channel.pipeline.addHTTPClientHandlers(withClientUpgrade: configuration)
                    }.flatMap {
                        channel.pipeline.addHandler(http)
                    }
                } catch {
                    return channel.eventLoop.makeFailedFuture(error)
                }
            }
        switch endpoint {
        case .unix(let path):
            return (try await bootstrap.connect(to: try SocketAddress(unixDomainSocketPath: path)).get(), signal)
        case .tcp(let host, let port, _):
            return (try await bootstrap.connect(host: host, port: port).get(), signal)
        }
    }

    private func writeText(_ data: Data, on channel: Channel) async throws {
        var buffer = channel.allocator.buffer(capacity: data.count)
        buffer.writeBytes(data)
        let frame = WebSocketFrame(fin: true, opcode: .text, maskKey: RexWebSocketMask.random(), data: buffer)
        try await channel.writeAndFlush(frame).get()
    }

    private func receive(_ text: String) async {
        guard let data = text.data(using: .utf8), data.count <= 1_048_576,
              let value = try? JSONDecoder().decode(JSONValue.self, from: data),
              let type = value["type"].string else { return }
        switch type {
        case "welcome":
            guard value["protocol"].string == "rex.control.v1",
                  let clientID = value["client"]["id"].string else { return }
            let serverRevision = value["api_server_revision"].int ?? value["api_revision"].int ?? 0
            let welcome = Welcome(clientID: clientID,
                                  reconnectToken: value["client"]["reconnect_token"].string,
                                  apiRevision: value["api_revision"].int ?? 0,
                                  apiServerRevision: serverRevision,
                                  maxMessageBytes: value["limits"]["max_message_bytes"].int ?? 1_048_576)
            self.welcome = welcome
            let waiter = welcomeWaiter; welcomeWaiter = nil
            waiter?.resume(returning: welcome)
        case "response":
            guard let id = value["id"].string, let entry = pending.removeValue(forKey: id) else { return }
            entry.timeout.cancel()
            let error = value["error"]
            if error.object != nil {
                entry.continuation.resume(throwing: BridgeError(error["code"].string ?? "rex_error",
                                                                 error["message"].string ?? "Rex request failed.",
                                                                 status: error["status"].int ?? 500))
            } else { entry.continuation.resume(returning: value["payload"]) }
        case "event":
            break
        default:
            break
        }
    }

    private func connectionClosed(code: Int, reason: String) async {
        channel = nil; welcome = nil
        let error = BridgeError("rex_unavailable", "The Rex connection closed (\(code)).", status: 503)
        upgradeSignal?.fail(error); upgradeSignal = nil
        failWelcome(error)
        for id in Array(pending.keys) { fail(id: id, error: error) }
    }

    private func failWelcome(_ error: any Error) {
        let waiter = welcomeWaiter; welcomeWaiter = nil
        waiter?.resume(throwing: error)
    }

    private func fail(id: String, error: any Error) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.timeout.cancel()
        entry.continuation.resume(throwing: error)
    }
}

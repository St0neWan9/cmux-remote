import Foundation
import CmuxRemoteCore

/// A stable shared client object; relocation changes transport without stranding open views.
public final class RemoteClient: Sendable {
    private let runtime: RemoteClientRuntime
    /// Host and device namespace for private pending operations; relocation keeps it stable.
    public let operationRecoveryScope: String
    public let canControlConversations: Bool
    public let canReplyFeed: Bool
    private let capabilities: Set<ClientCapability>
    private let legacy: Bool
    private let trace: @Sendable (String) -> Void
    /// One Bridge subscription per path, shared by every page and follower watching it.
    private let hub: PathWatchHub
    public func allows(_ capability: ClientCapability) -> Bool { capabilities.contains(capability) }
    /// Explicit legacy mode; the owner must separately enable it on the Bridge.
    ///
    /// `trace` receives one short line per dial, path outcome, link loss, failed or timed-out request and ended
    /// subscription. Lines never carry keys, grants, proofs, permits, bodies or query values.
    public init(pairing: PairingConfiguration, trace: @escaping @Sendable (String) -> Void = { _ in }) {
        legacy = true; self.trace = trace
        operationRecoveryScope = IdentityCryptography().digest(Data((pairing.certificateSHA256 + ":" + pairing.token).utf8))
        runtime = RemoteClientRuntime(pairing: pairing, connection: nil, trace: trace); canControlConversations = true; canReplyFeed = true; capabilities = Set(ClientCapability.allCases)
        hub = Self.hub(runtime: runtime, trace: trace)
    }
    public init(connection: AuthorizedConnection, trace: @escaping @Sendable (String) -> Void = { _ in }) throws {
        try connection.validate(); legacy = false; self.trace = trace
        operationRecoveryScope = IdentityCryptography().digest(try JSONEncoder().encode([connection.host.id, connection.grant.value.clientID]))
        let pairing = try PairingConfiguration(host: connection.endpoint.host, port: connection.endpoint.port, token: String(repeating: "0", count: 32), certificateSHA256: connection.host.certificateSHA256)
        runtime = RemoteClientRuntime(pairing: pairing, connection: connection, trace: trace)
        capabilities = Set(connection.grant.value.scope.capabilities)
        canControlConversations = connection.grant.value.scope.capabilities.contains(.conversationControl)
        canReplyFeed = connection.grant.value.scope.capabilities.contains(.feedReply)
        hub = Self.hub(runtime: runtime, trace: trace)
    }
    /// Keeps one path subscribed across link loss without dialing a link that is down; see `PathResubscription`.
    private static func hub(runtime: RemoteClientRuntime, trace: @escaping @Sendable (String) -> Void) -> PathWatchHub {
        let states = runtime.linkStates
        let loop = PathResubscription(subscribe: { try await runtime.subscribe($0) },
                                      linkDown: { states.latest == .disconnected }, linkUp: { await states.connected() },
                                      discardEpoch: { await runtime.discardEpoch() }, trace: trace)
        return PathWatchHub { path, changed in await loop.run(path, changed: changed) }
    }
    public func get<T: Decodable & Sendable>(_ path: String, query: [String: String] = [:], as type: T.Type) async throws -> T { try await runtime.request(path, method: "GET", query: query, body: nil, as: type) }
    public func post<B: Encodable & Sendable, T: Decodable & Sendable>(_ path: String, body: B, as type: T.Type) async throws -> T { try await runtime.request(path, method: "POST", query: [:], body: JSONEncoder().encode(body), as: type) }
    /// Fetches a bounded JPEG preview by a transcript-derived reference, never by host pathname.
    public func image(sessionID: String, reference: ConversationImageReference) async throws -> Data { try await runtime.image(sessionID: sessionID, reference: reference) }
    /// Coalesced invalidations; reconnection re-anchors reads and never repeats modifications.
    public func changes(paths: [String]) -> AsyncStream<Void> {
        let output = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        guard !paths.isEmpty, paths.count <= 4, Set(paths).count == paths.count else { output.continuation.finish(); return output.stream }
        let legacy = legacy, hub = hub, id = UUID(), continuation = output.continuation
        let task = Task {
            if legacy {
                while !Task.isCancelled {
                    continuation.yield(())
                    do { try await Task.sleep(for: .seconds(2)) } catch { break }
                }
                continuation.finish(); return
            }
            await hub.add(id, paths: Set(paths), changed: { continuation.yield(()) }, finished: { continuation.finish() })
        }
        // Removal waits for the registration, so a stream dropped at once still releases its subscriptions.
        output.continuation.onTermination = { _ in task.cancel(); Task { await task.value; await hub.remove(id) } }
        return output.stream
    }
    /// Refreshes host-certified cloud reachability without expanding the saved grant.
    public func refreshRelayHint() async throws -> AuthorizedConnection? { try await runtime.refreshRelayHint() }
    public func relocate(_ connection: AuthorizedConnection) async throws { try await runtime.relocate(connection) }
    /// Drops a link that may be dead and dials again, for a manual refresh or a network that came back.
    public func reconnect() async { await runtime.reconnect() }
    /// The link's state as it changes, starting with the current one once a dial has happened.
    public func linkStates() -> AsyncStream<LinkState> { runtime.linkStates.states() }
    public func close() { let runtime = runtime; Task { await runtime.close() } }
    deinit { let runtime = runtime; Task { await runtime.close() } }
}

import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// A scripted cloud peer: tests push inbound envelopes and read what the Bridge sent.
final class ScriptedRelaySocket: CloudRelayConnecting, @unchecked Sendable {
    private let inbound = AsyncThrowingStream<Data, any Error>.makeStream()
    private let outbound = AsyncStream<RelayEnvelope>.makeStream()
    private let lock = NSLock()
    private var iterator: AsyncThrowingStream<Data, any Error>.AsyncIterator?
    /// A path that died behind a proxy: pings are never answered and the socket reports nothing.
    private let silent: Bool
    /// Whether this scripted room answers the Bridge's liveness pings, and after how many it goes quiet the way
    /// a replaced Durable Object does. Answering here keeps the socket's own stream free for the test to read.
    private let answersPings: Bool
    private let stopsAnsweringAfter: Int?
    private var answered = 0
    private let closed = AsyncStream<Void>.makeStream()
    /// A silent socket answers neither its own pings nor the room's liveness pings.
    init(silent: Bool = false, answersPings: Bool? = nil, stopsAnsweringAfter: Int? = nil) {
        self.silent = silent; self.answersPings = answersPings ?? !silent; self.stopsAnsweringAfter = stopsAnsweringAfter
        iterator = inbound.stream.makeAsyncIterator()
    }
    var sent: AsyncStream<RelayEnvelope> { outbound.stream }
    func push(_ envelope: RelayEnvelope) throws { inbound.continuation.yield(try JSONEncoder().encode(envelope)) }
    func send(_ bytes: Data) async throws {
        let envelope = try JSONDecoder().decode(RelayEnvelope.self, from: bytes)
        outbound.continuation.yield(envelope)
        // The room answers a liveness ping itself; nothing else on the socket does.
        guard envelope.kind == "ping", answersPings else { return }
        let answered = lock.withLock { () -> Int in self.answered += 1; return self.answered }
        if let stopsAnsweringAfter, answered > stopsAnsweringAfter { return }
        try push(RelayEnvelope(kind: "pong"))
    }
    func receive() async throws -> Data {
        var current = lock.withLock { iterator }
        guard let data = try await current?.next() else { throw URLError(.networkConnectionLost) }
        lock.withLock { iterator = current }; return data
    }
    func ping() async throws { if silent { for await _ in closed.stream {}; throw URLError(.networkConnectionLost) } }
    func failureCode() -> String { "connection_failed" }
    func close() { inbound.continuation.finish(); outbound.continuation.finish(); closed.continuation.finish() }
}

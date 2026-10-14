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
    private let closed = AsyncStream<Void>.makeStream()
    init(silent: Bool = false) { self.silent = silent; iterator = inbound.stream.makeAsyncIterator() }
    var sent: AsyncStream<RelayEnvelope> { outbound.stream }
    func push(_ envelope: RelayEnvelope) throws { inbound.continuation.yield(try JSONEncoder().encode(envelope)) }
    func send(_ bytes: Data) async throws { outbound.continuation.yield(try JSONDecoder().decode(RelayEnvelope.self, from: bytes)) }
    func receive() async throws -> Data {
        var current = lock.withLock { iterator }
        guard let data = try await current?.next() else { throw URLError(.networkConnectionLost) }
        lock.withLock { iterator = current }; return data
    }
    func ping() async throws { if silent { for await _ in closed.stream {}; throw URLError(.networkConnectionLost) } }
    func failureCode() -> String { "connection_failed" }
    func close() { inbound.continuation.finish(); outbound.continuation.finish(); closed.continuation.finish() }
}

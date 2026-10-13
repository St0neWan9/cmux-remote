import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// Per-channel faults close one channel; the shared Bridge relay connection stays up for other phones.
@Suite struct CloudRelayChannelTests {
    @Test(.timeLimit(.minutes(1)))
    func lateDataAndDuplicateOpenCloseOnlyTheirChannel() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let socket = ScriptedRelaySocket(), dials = AsyncStream<Void>.makeStream(), ready = AsyncStream<Void>.makeStream()
        let service = SessionService(cmux: fixture.cmux, home: fixture.root.appendingPathComponent("home"), transcriptRoots: [fixture.root])
        let relay = try CloudRelayService(origin: "https://relay.example", secret: String(repeating: "a", count: 64),
            router: BridgeRouter(service: service, authority: fixture.authority), authority: fixture.authority,
            dial: { _, _ in dials.continuation.yield(()); return socket }, onConnected: { ready.continuation.yield(()) })
        do {
            try await relay.start()
            var sent = socket.sent.makeAsyncIterator()
            #expect(await sent.next()?.kind == "registry")
            try socket.push(RelayEnvelope(kind: "ready"))
            var connected = ready.stream.makeAsyncIterator(); #expect(await connected.next() != nil)
            // Data that crossed a revocation or local close in flight, for a channel Bridge no longer has.
            let stale = UUID().uuidString.lowercased()
            try socket.push(RelayEnvelope(kind: "data", channelID: stale, data: Data([1, 2, 3])))
            let closed = await nextChannelEnvelope(&sent)
            #expect(closed?.kind == "close"); #expect(closed?.channelID == stale)
            let live = UUID().uuidString.lowercased(), client = String(repeating: "c", count: 64)
            try socket.push(RelayEnvelope(kind: "open", channelID: live, clientID: client))
            try socket.push(RelayEnvelope(kind: "open", channelID: live, clientID: client))
            let duplicate = await nextChannelEnvelope(&sent)
            #expect(duplicate?.kind == "close"); #expect(duplicate?.channelID == live)
            #expect(await relay.status()["state"].string == "connected")
            var dialed = dials.stream.makeAsyncIterator(); _ = await dialed.next()
            // A restarted relay would redial after its one-second backoff.
            let redial = Task { await dialed.next() }
            try await Task.sleep(for: .seconds(2)); redial.cancel()
            #expect(await relay.status()["state"].string == "connected")
            await relay.stop(); await fixture.stop()
        } catch { await relay.stop(); await fixture.stop(); throw error }
    }
    /// Registry synchronization can interleave at any time; channel replies are what these tests inspect.
    private func nextChannelEnvelope(_ iterator: inout AsyncStream<RelayEnvelope>.AsyncIterator) async -> RelayEnvelope? {
        while let envelope = await iterator.next() { if envelope.kind != "registry" { return envelope } }
        return nil
    }
}

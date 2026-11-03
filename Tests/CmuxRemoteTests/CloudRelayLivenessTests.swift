import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// A relay path that dies behind a proxy keeps a socket open but never answers; the Bridge must notice and redial.
@Suite struct CloudRelayLivenessTests {
    private let fast = CloudRelayLiveness(pingInterval: .milliseconds(50), pongDeadline: .milliseconds(100), readyDeadline: .milliseconds(200))

    /// Hands out the scripted sockets in order and reports each dial.
    private final class Dialer: @unchecked Sendable {
        private let lock = NSLock(); private var sockets: [ScriptedRelaySocket]
        let dials = AsyncStream<Int>.makeStream(); private var count = 0
        init(_ sockets: [ScriptedRelaySocket]) { self.sockets = sockets }
        func next() -> ScriptedRelaySocket {
            let (socket, index) = lock.withLock { () -> (ScriptedRelaySocket, Int) in count += 1; return (sockets.isEmpty ? ScriptedRelaySocket() : sockets.removeFirst(), count) }
            dials.continuation.yield(index); return socket
        }
    }
    private func relay(_ fixture: LinkIntegrationFixture, _ dialer: Dialer, connected: AsyncStream<Void>.Continuation? = nil) throws -> CloudRelayService {
        let service = SessionService(cmux: fixture.cmux, home: fixture.root.appendingPathComponent("home"), transcriptRoots: [fixture.root])
        return try CloudRelayService(origin: "https://relay.example", secret: String(repeating: "a", count: 64),
            router: BridgeRouter(service: service, authority: fixture.authority), authority: fixture.authority,
            dial: { _, _ in dialer.next() }, liveness: fast, onConnected: { connected?.yield(()) })
    }

    @Test(.timeLimit(.minutes(1)))
    func aPathThatStopsAnsweringPingsIsRedialed() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let dead = ScriptedRelaySocket(silent: true), dialer = Dialer([dead])
        let relay = try relay(fixture, dialer)
        do {
            try await relay.start()
            var dials = dialer.dials.stream.makeAsyncIterator(); #expect(await dials.next() == 1)
            try dead.push(RelayEnvelope(kind: "ready"))
            // The unanswered ping closes the socket; the backoff then dials a fresh connection.
            #expect(await dials.next() == 2)
            await relay.stop(); await fixture.stop()
        } catch { await relay.stop(); await fixture.stop(); throw error }
    }

    @Test(.timeLimit(.minutes(1)))
    func aRegistrationTheRelayNeverAcknowledgesIsRedialed() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let mute = ScriptedRelaySocket(), dialer = Dialer([mute])
        let relay = try relay(fixture, dialer)
        do {
            try await relay.start()
            var dials = dialer.dials.stream.makeAsyncIterator(); #expect(await dials.next() == 1)
            #expect(await dials.next() == 2)
            #expect(await relay.status()["state"].string != "connected")
            await relay.stop(); await fixture.stop()
        } catch { await relay.stop(); await fixture.stop(); throw error }
    }

    /// A replaced Durable Object still carries frames but no longer knows this Bridge; only the room's own
    /// answer proves registration survived, so silence must end the link.
    @Test(.timeLimit(.minutes(1)))
    func aRoomThatStopsAnsweringLivenessPingsIsRedialed() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        // Answers two pings, then goes quiet the way a replaced room does.
        let socket = ScriptedRelaySocket(stopsAnsweringAfter: 2), dialer = Dialer([socket, ScriptedRelaySocket()])
        let relay = try relay(fixture, dialer)
        let pings = AsyncStream<String>.makeStream()
        let observing = Task { for await envelope in socket.sent where envelope.kind == "ping" { pings.continuation.yield(envelope.kind) } }
        do {
            try await relay.start()
            var dials = dialer.dials.stream.makeAsyncIterator(); #expect(await dials.next() == 1)
            try socket.push(RelayEnvelope(kind: "ready"))
            var seen = pings.stream.makeAsyncIterator()
            #expect(await seen.next() == "ping"); #expect(await seen.next() == "ping")
            #expect(await relay.status()["state"].string == "connected")
            // Without a pong the room no longer holds this registration, so the Bridge redials.
            #expect(await dials.next() == 2)
            observing.cancel(); await relay.stop(); await fixture.stop()
        } catch { observing.cancel(); await relay.stop(); await fixture.stop(); throw error }
    }

    @Test(.timeLimit(.minutes(1)))
    func aConnectionSynchronizesTheRegistryOnce() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let socket = ScriptedRelaySocket(), dialer = Dialer([socket]), ready = AsyncStream<Void>.makeStream()
        let relay = try relay(fixture, dialer, connected: ready.continuation)
        do {
            try await relay.start()
            var sent = socket.sent.makeAsyncIterator()
            #expect(await sent.next()?.kind == "registry")
            try socket.push(RelayEnvelope(kind: "ready"))
            var connected = ready.stream.makeAsyncIterator(); #expect(await connected.next() != nil)
            // Another registry send within a while would be a second, billable synchronization.
            let extra = Task { () -> String? in while let envelope = await sent.next() { if envelope.kind == "registry" { return envelope.kind } }; return nil }
            try await Task.sleep(for: .milliseconds(500)); extra.cancel()
            #expect(await extra.value == nil)
            await relay.stop(); await fixture.stop()
        } catch { await relay.stop(); await fixture.stop(); throw error }
    }
}

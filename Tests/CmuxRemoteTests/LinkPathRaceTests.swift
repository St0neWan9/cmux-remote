import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteClient

/// With a relay configured, every dial races the LAN against the relay and keeps the first to authenticate.
@Suite struct LinkPathRaceTests {
    @Test(.timeLimit(.minutes(1)))
    func anUnreachableLANRacesTheRelayFromTheFirstDial() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let dials = Counter(), traces = TraceLines()
        var transport: WebSocketTransport?
        do {
            try await fixture.authority.configureRelay(origin: "https://relay.example.com")
            let admission = try #require(try await fixture.authority.status(fixture.enrollmentRequest).value.relay)
            let bridge = fixture.connection.endpoint
            let pairing = try PairingConfiguration(host: bridge.host, port: bridge.port,
                token: String(repeating: "0", count: 32), certificateSHA256: fixture.connection.host.certificateSHA256)
            // Port 2 is a reserved system port that returns ECONNREFUSED immediately, so the
            // LAN path fails fast and the relay is the only path that can succeed.
            let link = WebSocketTransport(host: fixture.connection.host, key: fixture.connection.privateKey,
                endpoint: BridgeEndpoint(host: "127.0.0.1", port: 2, relay: admission),
                relayDial: { _, _ in
                    dials.increment()
                    var parts = URLComponents()
                    parts.scheme = "wss"; parts.host = bridge.host; parts.port = bridge.port; parts.path = "/v3/link"
                    return LinkSocket(url: parts.url!, delegate: PinnedSessionDelegate(pairing: pairing), timeout: 15)
                }, trace: { traces.append($0) }); transport = link
            // First request: both paths are dialled at once; the LAN is refused and the relay carries the link.
            let _: [SessionDescriptor] = try await request(link, connection: fixture.connection, path: "/v2/sessions")
            #expect(dials.value == 1)
            // The diagnostic log says why the LAN path was abandoned and which path took over, never the permit.
            let first = traces.lines
            #expect(first.first == "dial start path=race lan=127.0.0.1:2 relay=relay.example.com")
            let lanOutcome = try #require(first.first { $0.hasPrefix("dial lan ") })
            // The refusal normally lands first; if the relay is quicker the LAN is reported as having lost the race.
            if lanOutcome.hasPrefix("dial lan failed ") {
                #expect(lanOutcome.contains("unreachable=true"))
                #expect(lanOutcome.contains("error=URLError(") || lanOutcome.contains("error=POSIX("))
            } else { #expect(lanOutcome.hasSuffix(": relay connected first")) }
            #expect(!first.contains { $0.hasPrefix("dial fallback") })
            #expect(first.contains { $0.hasPrefix("dial relay ok ") && $0.hasSuffix("relayed=true") })
            #expect(first.contains("link connected relayed=true"))
            #expect(!first.contains { $0.contains("X-Cmux") || $0.contains("CmuxV2") })
            // After a reconnect the dial races both paths again, and the relay wins again with one more dial.
            await link.reconnect()
            let _: [SessionDescriptor] = try await request(link, connection: fixture.connection, path: "/v2/sessions")
            #expect(dials.value == 2)
            #expect(traces.lines.contains("reconnect requested: dropping link pending=0"))
            #expect(traces.lines.filter { $0 == "dial start path=race lan=127.0.0.1:2 relay=relay.example.com" }.count == 2)
            link.close(); await fixture.stop()
        } catch { transport?.close(); await fixture.stop(); throw error }
    }
    /// On the Mac's own network the LAN authenticates first and keeps the direct path; the relay that lost
    /// the race is closed and logged as cancelled, not as a failure the diagnostic log would flag.
    @Test(.timeLimit(.minutes(1)))
    func aReachableLANWinsTheRaceAndTheRelayIsCancelledNotFailed() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let silent = try SilentTCPListener()
        let dials = Counter(), traces = TraceLines()
        var transport: WebSocketTransport?
        do {
            try await fixture.authority.configureRelay(origin: "https://relay.example.com")
            let admission = try #require(try await fixture.authority.status(fixture.enrollmentRequest).value.relay)
            let bridge = fixture.connection.endpoint
            // The relay never answers, so it cannot win and is still dialing when the LAN authenticates.
            let link = WebSocketTransport(host: fixture.connection.host, key: fixture.connection.privateKey,
                endpoint: BridgeEndpoint(host: bridge.host, port: bridge.port, relay: admission),
                relayDial: { _, headers in
                    dials.increment()
                    return LinkSocket(url: URL(string: "wss://127.0.0.1:\(silent.port)/v3/link")!, headers: headers, timeout: 15)
                }, trace: { traces.append($0) }); transport = link
            let _: [SessionDescriptor] = try await request(link, connection: fixture.connection, path: "/v2/sessions")
            let lines = traces.lines
            #expect(lines.first == "dial start path=race lan=\(bridge.host):\(bridge.port) relay=relay.example.com")
            #expect(dials.value == 1)
            #expect(lines.contains { $0.hasPrefix("dial lan ok ") && $0.hasSuffix("relayed=false") })
            #expect(lines.contains("link connected relayed=false"))
            let loser = try #require(lines.first { $0.hasPrefix("dial relay ") })
            #expect(loser.hasPrefix("dial relay cancelled after ") && loser.hasSuffix("ms: lan connected first"))
            // The phone flags lines with "error=" or "timeout" as warnings; the race loser must carry neither.
            #expect(!loser.contains("error=") && !loser.contains("timeout"))
            #expect(!lines.contains { $0.contains("failed") && $0.contains("cancelled") })
            link.close(); silent.close(); await fixture.stop()
        } catch { transport?.close(); silent.close(); await fixture.stop(); throw error }
    }
    /// A LAN address that went quiet no longer holds the link back for its whole deadline: the relay dialled
    /// alongside it carries the link as soon as it authenticates, and the LAN dial is cancelled, not failed.
    @Test(.timeLimit(.minutes(1)))
    func aSilentLANDoesNotDelayTheRelay() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let silent = try SilentTCPListener()
        let traces = TraceLines()
        var transport: WebSocketTransport?
        do {
            try await fixture.authority.configureRelay(origin: "https://relay.example.com")
            let admission = try #require(try await fixture.authority.status(fixture.enrollmentRequest).value.relay)
            let bridge = fixture.connection.endpoint
            let pairing = try PairingConfiguration(host: bridge.host, port: bridge.port,
                token: String(repeating: "0", count: 32), certificateSHA256: fixture.connection.host.certificateSHA256)
            // The LAN accepts TCP but never answers TLS, and its deadline is far longer than the test's budget.
            let link = WebSocketTransport(host: fixture.connection.host, key: fixture.connection.privateKey,
                endpoint: BridgeEndpoint(host: "127.0.0.1", port: silent.port, relay: admission),
                relayDial: { _, _ in
                    var parts = URLComponents()
                    parts.scheme = "wss"; parts.host = bridge.host; parts.port = bridge.port; parts.path = "/v3/link"
                    return LinkSocket(url: parts.url!, delegate: PinnedSessionDelegate(pairing: pairing), timeout: 15)
                }, trace: { traces.append($0) }, lanDeadline: .seconds(40)); transport = link
            let started = ContinuousClock.now
            let _: [SessionDescriptor] = try await request(link, connection: fixture.connection, path: "/v2/sessions")
            #expect(ContinuousClock.now - started < .seconds(10), "The relay waited for the silent LAN")
            let lines = traces.lines
            #expect(lines.first == "dial start path=race lan=127.0.0.1:\(silent.port) relay=relay.example.com")
            #expect(lines.contains("link connected relayed=true"))
            let loser = try #require(lines.first { $0.hasPrefix("dial lan ") })
            #expect(loser.hasPrefix("dial lan cancelled after ") && loser.hasSuffix("ms: relay connected first"))
            #expect(!loser.contains("error=") && !loser.contains("timeout"))
            #expect(!lines.contains { $0.contains("failed") && $0.contains("cancelled") })
            link.close(); silent.close(); await fixture.stop()
        } catch { transport?.close(); silent.close(); await fixture.stop(); throw error }
    }
    /// A LAN that answers too slowly counts as unreachable: the dial must fall back to the relay, not fail with
    /// the "cancelled" error that closing the late socket can surface first.
    @Test(.timeLimit(.minutes(1)))
    func aLANHandshakeThatMissesItsDeadlineFallsBackToTheRelay() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let dials = Counter()
        var transport: WebSocketTransport?
        do {
            try await fixture.authority.configureRelay(origin: "https://relay.example.com")
            let admission = try #require(try await fixture.authority.status(fixture.enrollmentRequest).value.relay)
            let bridge = fixture.connection.endpoint
            let pairing = try PairingConfiguration(host: bridge.host, port: bridge.port,
                token: String(repeating: "0", count: 32), certificateSHA256: fixture.connection.host.certificateSHA256)
            // The LAN address is the real Bridge, but a one-millisecond deadline cannot be met.
            let link = WebSocketTransport(host: fixture.connection.host, key: fixture.connection.privateKey,
                endpoint: BridgeEndpoint(host: bridge.host, port: bridge.port, relay: admission),
                relayDial: { _, _ in
                    dials.increment()
                    var parts = URLComponents()
                    parts.scheme = "wss"; parts.host = bridge.host; parts.port = bridge.port; parts.path = "/v3/link"
                    return LinkSocket(url: parts.url!, delegate: PinnedSessionDelegate(pairing: pairing), timeout: 15)
                }, lanDeadline: .milliseconds(1)); transport = link
            for _ in 0..<5 {
                let _: [SessionDescriptor] = try await request(link, connection: fixture.connection, path: "/v2/sessions")
                await link.reconnect()
            }
            #expect(dials.value >= 5)
            link.close(); await fixture.stop()
        } catch { transport?.close(); await fixture.stop(); throw error }
    }
    private func request<T: Decodable & Sendable>(_ link: WebSocketTransport, connection: AuthorizedConnection, path: String) async throws -> T {
        let crypto = IdentityCryptography()
        let announcement = try await link.request("/v2/identity", method: "GET", as: SignedValue<HostAnnouncement>.self)
        try crypto.verify(announcement, domain: "host", publicKey: connection.host.publicKey)
        return try await link.request(path, method: "GET", authorization: { uri, bytes in
            let proof = RequestProof(epoch: announcement.value.epoch, hostID: connection.host.id,
                clientID: connection.grant.value.clientID, method: "GET", uri: uri,
                bodySHA256: crypto.digest(bytes), nonce: UUID().uuidString, timestamp: Int(Date().timeIntervalSince1970))
            return "CmuxV2 " + (try JSONEncoder().encode(crypto.sign(proof, domain: "request", privateKey: connection.privateKey))).base64EncodedString()
        }, as: T.self)
    }
}

private final class TraceLines: @unchecked Sendable {
    private let lock = NSLock(); private var values: [String] = []
    var lines: [String] { lock.withLock { values } }
    func append(_ line: String) { lock.withLock { values.append(line) } }
}

private final class Counter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    var value: Int { lock.withLock { count } }
    func increment() { lock.withLock { count += 1 } }
}

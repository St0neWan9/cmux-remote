import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteClient

@Suite struct LinkReconnectTests {
    /// The phone shows "reconnecting" while it dials and clears it once the link is back.
    @Test(.timeLimit(.minutes(1))) func aManualReconnectReportsDialingThenConnected() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let client = try RemoteClient(connection: fixture.connection)
        do {
            _ = try await client.get("/v1/sessions", as: [SessionDescriptor].self)
            var states = client.linkStates().makeAsyncIterator()
            #expect(await states.next() == .connected)
            await client.reconnect()
            // The dropped link reports its loss before the new dial, so a view never shows a stale "connected".
            #expect(await states.next() == .disconnected)
            #expect(await states.next() == .connecting)
            #expect(await states.next() == .connected)
            // The new link carries requests without another dial.
            _ = try await client.get("/v1/sessions", as: [SessionDescriptor].self)
            client.close(); await fixture.stop()
        } catch { client.close(); await fixture.stop(); throw error }
    }
    /// A Mac that went away is reported as disconnected, not left looking connected.
    @Test(.timeLimit(.minutes(1))) func aLostBridgeReportsDisconnected() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let client = try RemoteClient(connection: fixture.connection)
        _ = try await client.get("/v1/sessions", as: [SessionDescriptor].self)
        var states = client.linkStates().makeAsyncIterator()
        #expect(await states.next() == .connected)
        await fixture.stop()
        await client.reconnect()
        var seen: [LinkState] = []
        while let state = await states.next() { seen.append(state); if seen.count >= 3 { break } }
        #expect(seen.first == .disconnected)
        #expect(seen.last == .disconnected)
        client.close()
    }
    @Test func aNewObserverStartsFromTheCurrentStateAndRepeatsAreDropped() async {
        let states = LinkStateBroadcaster()
        states.report(.connecting); states.report(.connected); states.report(.connected)
        var first = states.states().makeAsyncIterator()
        #expect(await first.next() == .connected)
        states.report(.disconnected)
        #expect(await first.next() == .disconnected)
        states.finish()
        #expect(await first.next() == nil)
    }
}

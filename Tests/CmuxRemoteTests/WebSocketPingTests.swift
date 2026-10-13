import Foundation
import Testing
import CmuxRemoteCore

@Suite struct WebSocketPingTests {
    /// Resuming a checked continuation twice traps the process, which is how a relay heartbeat crashed the Bridge.
    @Test func aRepeatedPingResultSettlesOnce() async throws {
        let ping = WebSocketPing()
        // The second result must not settle the ping again: the process would trap.
        do { try await ping.run { handler in handler(URLError(.cannotConnectToHost)); handler(URLError(.cannotConnectToHost)) } }
        catch { #expect((error as? URLError)?.code == .cannotConnectToHost) }
    }
    @Test func theFirstResultWins() async throws {
        let ping = WebSocketPing()
        do {
            try await ping.run { handler in
                handler(URLError(.timedOut))
                handler(nil)
            }
            Issue.record("The first result must settle the ping")
        } catch { #expect((error as? URLError)?.code == .timedOut) }
    }
    @Test func aSettledPingIsNotDisturbedByLaterResults() async throws {
        let ping = WebSocketPing()
        try await ping.run { $0(nil) }
        // A ping that already answered cannot trap on a stray result.
        ping.settle(nil)
        ping.cancel()
    }
    @Test func cancellingSettlesAPendingPing() async throws {
        let ping = WebSocketPing()
        let waiter = Task { try await ping.run { _ in } }
        // Give the waiter a chance to start before the heartbeat is cancelled.
        while await ping.isPendingForTesting == false { try await Task.sleep(for: .milliseconds(1)) }
        ping.cancel()
        do { try await waiter.value; Issue.record("A cancelled ping must not report success") }
        catch { #expect(error is CancellationError) }
    }
}

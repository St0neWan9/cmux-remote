import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
@testable import CmuxRemoteClient

/// Late frames for work this client already abandoned must not end the shared link.
@Suite struct LinkCancellationTests {
    @Test(.timeLimit(.minutes(1)))
    func cancellingOneMultiChunkReadKeepsConcurrentRequestsAlive() async throws {
        let fixture = try await LinkIntegrationFixture.create(text: String(repeating: "chunked ", count: 20_000), recordCount: 8)
        let client = try RemoteClient(connection: fixture.connection)
        do {
            _ = try await client.get("/v1/sessions", as: [SessionDescriptor].self)
            for delay in [0, 1, 2, 4, 8, 16] {
                let abandoned = Task { try await client.get("/v1/sessions/demo-session/history", as: ConversationSnapshot.self) }
                let kept = Task { try await client.get("/v1/sessions/demo-session/history", as: ConversationSnapshot.self) }
                try await Task.sleep(for: .milliseconds(delay))
                abandoned.cancel()
                #expect(try await kept.value.messages.count == 8)
            }
            client.close(); await fixture.stop()
        } catch { client.close(); await fixture.stop(); throw error }
    }
    @Test(.timeLimit(.minutes(1)))
    func cancellingSubscriptionsDoesNotTurnAnInFlightSendIntoAnUnknownOutcome() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let client = try RemoteClient(connection: fixture.connection)
        do {
            for index in 0..<6 {
                let started = AsyncStream<Void>.makeStream()
                let watcher = Task {
                    for await _ in client.changes(paths: ["/v1/sessions/demo-session/history", "/v1/sessions"]) { started.continuation.yield(()) }
                }
                var first = started.stream.makeAsyncIterator(); _ = await first.next()
                let send = Task { try await client.post("/v1/sessions/demo-session/send", body: SendRequest(text: "Message " + String(index)), as: MutationReceipt.self) }
                // Cancelling the watcher cancels both subscriptions while their events and the send share the link.
                watcher.cancel()
                _ = try await send.value
            }
            client.close(); await fixture.stop()
        } catch { client.close(); await fixture.stop(); throw error }
    }
    @Test(.timeLimit(.minutes(1)))
    func idleLinkSurvivesLongerThanTheHandshakeDeadline() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        var raw: LinkRawConnection?
        do {
            var connection = try await LinkRawConnection.connect(fixture.connection); raw = connection
            try await Task.sleep(for: .seconds(6))
            let id = try await connection.read("/v2/sessions", connection: fixture.connection)
            let response = try await connection.next()
            #expect(response.id == id); #expect(response.status == 200)
            connection.socket.close(); await fixture.stop()
        } catch { raw?.socket.close(); await fixture.stop(); throw error }
    }
}

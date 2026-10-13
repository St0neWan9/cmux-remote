import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge
@testable import CmuxRemoteClient

@Suite struct LinkBoundaryTests {
    @Test func signedProofCannotBeBorrowedByAnotherHandshakeIdentity() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        var raw: LinkRawConnection?
        do {
            var connection = try await LinkRawConnection.connect(fixture.connection, signingKey: IdentityCryptography().generatePrivateKey())
            raw = connection
            _ = try await connection.read("/v2/sessions", connection: fixture.connection)
            do { _ = try await connection.next(); Issue.record("Borrowed proof must not expose any resource") } catch {}
            connection.socket.close(); await fixture.stop()
        } catch { raw?.socket.close(); await fixture.stop(); throw error }
    }
    @Test(.timeLimit(.minutes(1)))
    func slowConsumerDoesNotBlockOtherRequestsAndIsEventuallyDisconnected() async throws {
        let fixture = try await LinkIntegrationFixture.create(text: String(repeating: "bounded ", count: 20_000), recordCount: 8)
        var raw: LinkRawConnection?
        do {
            var connection = try await LinkRawConnection.connect(fixture.connection); raw = connection
            let stalled = try await connection.read("/v2/sessions/demo-session/history", connection: fixture.connection)
            let first = try await connection.next()
            #expect(first.id == stalled); #expect(first.final == false); #expect(first.data?.count == 65_536)
            let other = try await connection.read("/v2/sessions", connection: fixture.connection)
            let response = try await connection.next(); #expect(response.id == other); #expect(response.final == true)
            try await connection.ack(response)
            // No acknowledgement for the first request: observe its actual production deadline.
            do { _ = try await connection.next(); Issue.record("Slow link must close instead of buffering indefinitely") } catch {}
            connection.socket.close(); await fixture.stop()
        } catch { raw?.socket.close(); await fixture.stop(); throw error }
    }
    @Test func ownerRelayConfigurationDoesNotStartSharingOrExpandGrants() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        do {
            let file = fixture.root.appendingPathComponent("registration-key")
            try Data(String(repeating: "b", count: 64).utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let service = SessionService(cmux: fixture.cmux, home: fixture.root.appendingPathComponent("home"), transcriptRoots: [fixture.root])
            let sharing = ManagedSharingService(state: BridgeState(directory: fixture.root), authority: fixture.authority, router: BridgeRouter(service: service, authority: fixture.authority), port: 0, advertise: false)
            let status = try await sharing.configureRelay(origin: "https://relay.example", keyFile: file.path)
            #expect(status["state"].string == "stopped"); #expect(status["relay"]["state"].string == "stopped")
            #expect(try await fixture.authority.currentClient(fixture.connection.grant.value.clientID).grant.signature == fixture.connection.grant.signature)
            let removed = try await sharing.configureRelay(origin: nil, keyFile: nil)
            #expect(removed["relay"] == .null)
            _ = try await sharing.start()
            do { _ = try await sharing.configureRelay(origin: "https://relay.example", keyFile: file.path); Issue.record("Sharing must be off before changing relay configuration") }
            catch { #expect((error as? BridgeError)?.code == "sharing_busy") }
            _ = await sharing.stop(); await fixture.stop()
        } catch { await fixture.stop(); throw error }
    }
}

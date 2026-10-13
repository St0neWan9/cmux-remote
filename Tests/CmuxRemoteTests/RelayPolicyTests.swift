import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

@Suite struct RelayPolicyTests {
    @Test(arguments: ["http://relay.example", "https://user:pass@relay.example", "https://relay.example/x", "https://relay.example?q=1", "https://relay.example#fragment"])
    func relayOriginRejectsCredentialsAndUnscopedURLs(_ value: String) {
        #expect(throws: (any Error).self) { try RelayOrigin(value) }
    }
    @Test func unchangedJSONDoesNotCauseFalseSubscriptionUpdates() throws {
        let digest = LinkObservationDigest()
        let a = Data(#"{"items":[{"state":"idle","id":"same"}],"count":1}"#.utf8)
        let b = Data(#"{"count":1,"items":[{"id":"same","state":"idle"}]}"#.utf8)
        #expect(try digest.digest(a) == digest.digest(b))
        let changed = Data(#"{"count":1,"items":[{"id":"same","state":"working"}]}"#.utf8)
        #expect(try digest.digest(a) != digest.digest(changed))
    }
    @Test func privateRegistrationFilesCannotBeSymlinksPublicOrOversized() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("secret")
        try Data(String(repeating: "a", count: 64).utf8).write(to: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let repository = RelayConfigurationRepository(directory: root)
        _ = try repository.save(origin: "https://RELAY.example:443/", keyFile: file.path)
        #expect(try repository.load()?.origin == "https://relay.example")
        let alias = root.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)
        #expect(throws: (any Error).self) { try repository.save(origin: "https://relay.example", keyFile: alias.path) }
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        #expect(throws: (any Error).self) { try repository.load() }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try Data(repeating: 65, count: 600).write(to: file)
        #expect(throws: (any Error).self) { try repository.load() }
        try repository.remove(); #expect(try repository.load() == nil)
    }
    @Test func laneAdmissionIsBoundedAndReleasedOnlyForItsOwnChannel() async {
        let pool = LinkAdmissionPool(maximum: 1)
        let first = NSObject(), second = NSObject()
        let a = ObjectIdentifier(first), b = ObjectIdentifier(second)
        #expect(await pool.reserve(a)); #expect(!(await pool.reserve(b)))
        await pool.release(b); #expect(!(await pool.reserve(b)))
        await pool.release(a); #expect(await pool.reserve(b))
    }
    @Test func enrollmentRelayPermitIsSignedAndApprovedProofHasNoResourceScope() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        do {
            try await fixture.authority.configureRelay(origin: "https://relay.example")
            let bootstrap = try await fixture.authority.open(endpoint: fixture.connection.endpoint, workspaces: fixture.connection.grant.value.scope.workspaces)
            try EnrollmentLinkCodec().validate(bootstrap, now: Int(Date().timeIntervalSince1970))
            let guest = try #require(bootstrap.value.endpoint.relay)
            #expect(guest.admission.value.kind == "enrollment")
            #expect(throws: (any Error).self) { try guest.validate(host: fixture.connection.host, clientPublicKey: "other") }
            let status = try await fixture.authority.status(fixture.enrollmentRequest)
            let approved = try #require(status.value.relay)
            var connection = fixture.connection; connection.endpoint.relay = approved; try connection.validate()
            #expect(approved.admission.value.kind == "approved")
            #expect(approved.admission.value.expiresAt == nil)
            let relocated = try connection.relocated(to: fixture.connection.endpoint, advertisedHost: connection.host)
            #expect(relocated.endpoint.relay == approved)
            #expect(throws: (any Error).self) { try approved.validate(host: fixture.connection.host, clientPublicKey: IdentityCryptography().publicKey(privateKey: IdentityCryptography().generatePrivateKey())) }
            await fixture.stop()
        } catch { await fixture.stop(); throw error }
    }
}

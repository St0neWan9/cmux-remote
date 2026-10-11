import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

private struct EnrollmentFixture {
    let directory: URL
    let hostKey: Data
    let host: HostIdentity
    let clockFile: URL
    let authority: ConnectionAuthority
    let workspace = "11111111-1111-1111-1111-111111111111"
    init() throws {
        let crypto = IdentityCryptography()
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        hostKey = crypto.generatePrivateKey(); let key = try crypto.publicKey(privateKey: hostKey)
        host = HostIdentity(id: try crypto.identityID(publicKey: key), publicKey: key, certificateSHA256: String(repeating: "a", count: 64), name: "Fixture")
        clockFile = directory.appendingPathComponent("clock"); try Data("1000".utf8).write(to: clockFile)
        let clock = clockFile
        authority = try ConnectionAuthority(host: host, privateKey: hostKey, registryFile: directory.appendingPathComponent("clients.json"), now: { Int((try? String(contentsOf: clock, encoding: .utf8)) ?? "1000") ?? 1000 })
    }
    func request(_ bootstrap: SignedValue<EnrollmentBootstrap>, key: Data, kind: String = "iphone") throws -> SignedValue<EnrollmentRequest> {
        let crypto = IdentityCryptography(); let publicKey = try crypto.publicKey(privateKey: key)
        let request = EnrollmentRequest(hostID: host.id, windowID: bootstrap.value.windowID, requestID: UUID().uuidString, clientID: try crypto.identityID(publicKey: publicKey), clientPublicKey: publicKey, clientName: "Fixture " + kind, clientKind: kind, nonce: UUID().uuidString, scope: ClientScope(workspaces: [workspace], capabilities: ClientCapability.allCases), expiresAt: bootstrap.value.expiresAt)
        return try crypto.sign(request, domain: "enrollment-request", privateKey: key)
    }
    func header(key: Data, clientID: String, epoch: String, nonce: String = UUID().uuidString, method: String = "GET", uri: String = "/v2/sessions", body: Data = Data()) throws -> String {
        let crypto = IdentityCryptography(); let proof = RequestProof(epoch: epoch, hostID: host.id, clientID: clientID, method: method, uri: uri, bodySHA256: crypto.digest(body), nonce: nonce, timestamp: 1000)
        return "CmuxV2 " + (try JSONEncoder().encode(crypto.sign(proof, domain: "request", privateKey: key))).base64EncodedString()
    }
    func clean() { try? FileManager.default.removeItem(at: directory) }
}

@Suite struct EnrollmentTests {
    @Test func qrContainsHostTrustAndExpiringWindowWithoutADeviceCredential() async throws {
        let f = try EnrollmentFixture(); defer { f.clean() }
        let bootstrap = try await f.authority.open(endpoint: BridgeEndpoint(host: "127.0.0.1", port: 7740), workspaces: [f.workspace])
        let link = try EnrollmentLinkCodec().encode(bootstrap)
        #expect(try EnrollmentLinkCodec().decode(link, now: 1000).value == bootstrap.value)
        let payload = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(bootstrap))
        #expect(payload["value"]["token"] == .null)
        #expect(payload["value"]["privateKey"] == .null)
        var forged = bootstrap; forged.value.endpoint.host = "attacker.invalid"
        do { _ = try EnrollmentLinkCodec().decode(EnrollmentLinkCodec().encode(forged), now: 1000); Issue.record("Expected altered QR rejection") }
        catch { #expect((error as? BridgeError)?.code == "invalid_signature") }
        do { _ = try EnrollmentLinkCodec().decode(link, now: 1400); Issue.record("Expected expired QR rejection") }
        catch { #expect((error as? BridgeError)?.code == "enrollment_expired") }
    }
    @Test func approvalIsBoundToOneConcurrentClientAndCanBeNarrowed() async throws {
        let f = try EnrollmentFixture(); defer { f.clean() }
        let bootstrap = try await f.authority.open(endpoint: BridgeEndpoint(host: "127.0.0.1", port: 7740), workspaces: [f.workspace])
        let crypto = IdentityCryptography()
        let phone = try f.request(bootstrap, key: crypto.generatePrivateKey()); let mac = try f.request(bootstrap, key: crypto.generatePrivateKey(), kind: "mac")
        _ = try await f.authority.submit(phone); _ = try await f.authority.submit(mac)
        let scope = ClientScope(workspaces: [f.workspace], capabilities: [.workspaceRead, .conversationRead])
        try await f.authority.approve(requestID: phone.value.requestID, scope: scope)
        let approved = try await f.authority.status(phone)
        #expect(approved.value.state == "approved")
        #expect(approved.value.grant?.value.clientID == phone.value.clientID)
        #expect(approved.value.grant?.value.nonce == phone.value.nonce)
        #expect(approved.value.grant?.value.scope == scope)
        #expect(try await f.authority.status(mac).value.state == "pending")
        try await f.authority.deny(requestID: mac.value.requestID)
        #expect(try await f.authority.status(mac).value.grant == nil)
    }
    @Test func closedExpiredCancelledAndForgedRequestsNeverIssueGrants() async throws {
        let f = try EnrollmentFixture(); defer { f.clean() }
        let crypto = IdentityCryptography(); let key = crypto.generatePrivateKey()
        let bootstrap = try await f.authority.open(endpoint: BridgeEndpoint(host: "127.0.0.1", port: 7740), workspaces: [f.workspace])
        let request = try f.request(bootstrap, key: key)
        var forged = request; forged.value.clientName = "Another device"
        do { _ = try await f.authority.submit(forged); Issue.record("Expected proof rejection") }
        catch { #expect((error as? BridgeError)?.code == "invalid_signature") }
        _ = try await f.authority.submit(request); _ = try await f.authority.cancel(request)
        do { try await f.authority.approve(requestID: request.value.requestID, scope: request.value.scope); Issue.record("Cancelled request approved") }
        catch { #expect((error as? BridgeError)?.code == "request_expired") }
        let expiring = try f.request(bootstrap, key: crypto.generatePrivateKey()); _ = try await f.authority.submit(expiring)
        try Data("1400".utf8).write(to: f.clockFile)
        #expect(try await f.authority.status(expiring).value.state == "expired")
        do { try await f.authority.approve(requestID: expiring.value.requestID, scope: expiring.value.scope); Issue.record("Expired request approved") }
        catch { #expect((error as? BridgeError)?.code == "request_expired") }
        await f.authority.closeEnrollment()
        #expect(try await f.authority.status(expiring).value.grant == nil)
    }
    @Test func authorizationRejectsReplayChangedContentWrongHostAndRevokedClientsAcrossRestart() async throws {
        let f = try EnrollmentFixture(); defer { f.clean() }
        let key = IdentityCryptography().generatePrivateKey()
        let bootstrap = try await f.authority.open(endpoint: BridgeEndpoint(host: "127.0.0.1", port: 7740), workspaces: [f.workspace])
        let request = try f.request(bootstrap, key: key); _ = try await f.authority.submit(request)
        try await f.authority.approve(requestID: request.value.requestID, scope: request.value.scope)
        let header = try f.header(key: key, clientID: request.value.clientID, epoch: f.authority.epoch)
        _ = try await f.authority.authorize(header: header, method: "GET", uri: "/v2/sessions", body: Data())
        do { _ = try await f.authority.authorize(header: header, method: "GET", uri: "/v2/sessions", body: Data()); Issue.record("Expected replay rejection") }
        catch { #expect((error as? BridgeError)?.code == "replayed_request") }
        let changed = try f.header(key: key, clientID: request.value.clientID, epoch: f.authority.epoch)
        do { _ = try await f.authority.authorize(header: changed, method: "POST", uri: "/v2/sessions", body: Data("changed".utf8)); Issue.record("Expected content rejection") }
        catch { #expect((error as? BridgeError)?.code == "invalid_proof") }
        let restarted = try ConnectionAuthority(host: f.host, privateKey: f.hostKey, registryFile: f.directory.appendingPathComponent("clients.json"), now: { 1000 })
        do { _ = try await restarted.authorize(header: changed, method: "GET", uri: "/v2/sessions", body: Data()); Issue.record("Expected old epoch rejection") }
        catch { #expect((error as? BridgeError)?.code == "invalid_proof") }
        try await restarted.revoke(clientID: request.value.clientID)
        let proof = try f.header(key: key, clientID: request.value.clientID, epoch: restarted.epoch)
        do { _ = try await restarted.authorize(header: proof, method: "GET", uri: "/v2/sessions", body: Data()); Issue.record("Expected revocation rejection") }
        catch { #expect((error as? BridgeError)?.code == "unauthorized") }
    }
}

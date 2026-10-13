import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

/// Relay-directory windows let a phone request access without a QR; the owner still approves the exact device.
@Suite struct DirectoryEnrollmentTests {
    private let workspaces = ["11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"]
    private func authority() throws -> (ConnectionAuthority, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let state = BridgeState(directory: root); try state.initialize()
        return (try state.authority(name: "Directory host"), root)
    }
    private func request(_ bootstrap: SignedValue<EnrollmentBootstrap>) throws -> SignedValue<EnrollmentRequest> {
        let crypto = IdentityCryptography(), key = crypto.generatePrivateKey(), publicKey = try crypto.publicKey(privateKey: key)
        let value = EnrollmentRequest(hostID: bootstrap.value.host.id, windowID: bootstrap.value.windowID, requestID: UUID().uuidString, clientID: try crypto.identityID(publicKey: publicKey), clientPublicKey: publicKey, clientName: "Phone", clientKind: "iphone", nonce: UUID().uuidString, scope: ClientScope(workspaces: bootstrap.value.workspaces, capabilities: [.workspaceRead, .conversationRead]), expiresAt: bootstrap.value.expiresAt)
        return try crypto.sign(value, domain: "enrollment-request", privateKey: key)
    }
    @Test func directoryRequestSurvivesQRWindowsAndRotationAndOwnerCanNarrowIt() async throws {
        let (authority, root) = try authority(); defer { try? FileManager.default.removeItem(at: root) }
        let endpoint = BridgeEndpoint(host: "192.168.1.2", port: 7740)
        do { _ = try await authority.openDirectory(endpoint: endpoint, workspaces: workspaces); Issue.record("A directory listing needs a relay") }
        catch { #expect((error as? BridgeError)?.code == "relay_configuration") }
        try await authority.configureRelay(origin: "https://relay.example")
        let listed = try await authority.openDirectory(endpoint: endpoint, workspaces: workspaces)
        try EnrollmentLinkCodec().validate(listed, now: Int(Date().timeIntervalSince1970))
        #expect(listed.value.endpoint.relay?.admission.value.kind == "enrollment")
        let phone = try request(listed)
        #expect(try await authority.submit(phone).value.state == "pending")
        // A QR window and one rotation later, the listed request is still the owner's to decide.
        _ = try await authority.open(endpoint: endpoint, workspaces: [workspaces[0]])
        _ = try await authority.openDirectory(endpoint: endpoint, workspaces: workspaces)
        #expect(try await authority.status(phone).value.state == "pending")
        let narrowed = ClientScope(workspaces: [workspaces[1]], capabilities: [.workspaceRead, .conversationRead])
        try await authority.approve(requestID: phone.value.requestID, scope: narrowed)
        let approved = try await authority.status(phone).value
        #expect(approved.state == "approved"); #expect(approved.grant?.value.scope.workspaces == [workspaces[1]])
    }
    @Test func stoppingTheDirectoryEndsApprovalOfListedRequests() async throws {
        let (authority, root) = try authority(); defer { try? FileManager.default.removeItem(at: root) }
        try await authority.configureRelay(origin: "https://relay.example")
        let listed = try await authority.openDirectory(endpoint: BridgeEndpoint(host: "192.168.1.2", port: 7740), workspaces: workspaces)
        let phone = try request(listed); _ = try await authority.submit(phone)
        await authority.closeDirectory()
        do { try await authority.approve(requestID: phone.value.requestID, scope: phone.value.scope); Issue.record("A closed directory window must not be approvable") }
        catch { #expect((error as? BridgeError)?.code == "request_expired") }
        do { _ = try await authority.submit(try request(listed)); Issue.record("A closed directory window must not accept requests") }
        catch { #expect((error as? BridgeError)?.code == "enrollment_closed") }
    }
}

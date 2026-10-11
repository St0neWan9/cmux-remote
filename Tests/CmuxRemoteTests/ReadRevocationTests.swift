import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

private actor ReadRevocationCmux: CmuxControlling {
    let workspace = "11111111-1111-1111-1111-111111111111"
    let surface = "22222222-2222-2222-2222-222222222222"
    let authority: ConnectionAuthority
    let clientID: String
    var didRevoke = false
    init(authority: ConnectionAuthority, clientID: String) { self.authority = authority; self.clientID = clientID }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions": return .object(["sessions": .array([.object(["session_id": .string("session"), "agent": .string("claude"), "title": .string("Session")])])])
        case "chat.sessions.dump": return .object(["sessions": .array([.object(["session_id": .string("session"), "agent": .string("claude"), "workspace_id": .string(workspace), "surface_id": .string(surface), "state": .string("idle")])])])
        case "surface.read_text":
            try await authority.revoke(clientID: clientID); didRevoke = true
            return .object(["text": .string("⏺ Private revoked text.\nThinking… (esc to interrupt)\n❯")])
        default: return .object([:])
        }
    }
}
@Suite struct ReadRevocationTests {
    @Test func previewIsDeniedWhenDeviceRevokedDuringBackendRead() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let crypto = IdentityCryptography(), hostKey = IdentityCryptography().generatePrivateKey(), key = IdentityCryptography().generatePrivateKey()
        let pub = try crypto.publicKey(privateKey: hostKey)
        let host = HostIdentity(id: try crypto.identityID(publicKey: pub), publicKey: pub, certificateSHA256: String(repeating: "a", count: 64), name: "Host")
        let authority = try ConnectionAuthority(host: host, privateKey: hostKey, registryFile: dir.appendingPathComponent("clients.json"), now: { 1000 })
        let bootstrap = try await authority.open(endpoint: BridgeEndpoint(host: "127.0.0.1", port: 7740), workspaces: ["11111111-1111-1111-1111-111111111111"])
        let clientPub = try crypto.publicKey(privateKey: key), clientID = try crypto.identityID(publicKey: clientPub)
        let scope = ClientScope(workspaces: bootstrap.value.workspaces, capabilities: [.conversationRead])
        let enrollment = EnrollmentRequest(hostID: host.id, windowID: bootstrap.value.windowID, requestID: UUID().uuidString, clientID: clientID, clientPublicKey: clientPub, clientName: "Phone", clientKind: "iphone", nonce: UUID().uuidString, scope: scope, expiresAt: bootstrap.value.expiresAt)
        _ = try await authority.submit(crypto.sign(enrollment, domain: "enrollment-request", privateKey: key))
        try await authority.approve(requestID: enrollment.requestID, scope: scope)
        let cmux = ReadRevocationCmux(authority: authority, clientID: clientID)
        let service = SessionService(cmux: cmux, home: dir, transcriptRoots: [])
        let router = BridgeRouter(service: service, authority: authority)
        let proof = RequestProof(epoch: authority.epoch, hostID: host.id, clientID: clientID, method: "GET", uri: "/v2/sessions/session/preview", bodySHA256: crypto.digest(Data()), nonce: UUID().uuidString, timestamp: 1000)
        let header = "CmuxV2 " + (try JSONEncoder().encode(crypto.sign(proof, domain: "request", privateKey: key))).base64EncodedString()
        let result = await router.respond(method: "GET", uri: proof.uri, authorization: header, body: Data())
        #expect(await cmux.didRevoke)
        #expect(try await authority.enrolledClients()[0].revoked)
        #expect(result.0 == 401)
        #expect(!String(decoding: result.1, as: UTF8.self).contains("Private revoked text."))
    }
}

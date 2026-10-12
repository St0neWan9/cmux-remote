import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

private actor AuthorizationRaceCmux: CmuxControlling {
    let allowed = "11111111-1111-1111-1111-111111111111"
    let forbidden = "33333333-3333-3333-3333-333333333333"
    let surface = "22222222-2222-2222-2222-222222222222"
    let authority: ConnectionAuthority
    let clientID: String
    let revokeDuringRefresh: Bool
    var sends = 0
    init(authority: ConnectionAuthority, clientID: String, revokeDuringRefresh: Bool) {
        self.authority = authority; self.clientID = clientID; self.revokeDuringRefresh = revokeDuringRefresh
    }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions": return .object(["sessions": .array([.object(["session_id": .string("session"), "agent": .string("claude"), "title": .string("Session")])])])
        case "chat.sessions.dump":
            return .object(["sessions": .array([.object(["session_id": .string("session"), "agent": .string("claude"), "workspace_id": .string(allowed), "surface_id": .string(surface), "state": .string("idle")])])])
        case "surface.input_state":
            // Mutate during the actual backend read, independent of how many
            // preliminary discovery requests a router happens to perform.
            if revokeDuringRefresh { try await authority.revoke(clientID: clientID) }
            return .object(["agent": .bool(true), "workspace_id": revokeDuringRefresh ? (params["workspace_id"] ?? .null) : .string(forbidden), "surface_id": params["surface_id"] ?? .null, "blocks_typing": .bool(false)])
        case "mobile.chat.send": sends += 1; return .object(["submitted": .bool(true)])
        default: return .object([:])
        }
    }
}

@Suite struct AuthorizationRaceTests {
    private func exercise(revoke: Bool) async throws -> (Int, Int, Bool) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let crypto = IdentityCryptography(), hostKey = IdentityCryptography().generatePrivateKey(), key = IdentityCryptography().generatePrivateKey()
        let pub = try crypto.publicKey(privateKey: hostKey)
        let host = HostIdentity(id: try crypto.identityID(publicKey: pub), publicKey: pub, certificateSHA256: String(repeating: "a", count: 64), name: "Host")
        let authority = try ConnectionAuthority(host: host, privateKey: hostKey, registryFile: dir.appendingPathComponent("clients.json"), now: { 1000 })
        let bootstrap = try await authority.open(endpoint: BridgeEndpoint(host: "127.0.0.1", port: 7740), workspaces: ["11111111-1111-1111-1111-111111111111"])
        let clientPub = try crypto.publicKey(privateKey: key), clientID = try crypto.identityID(publicKey: clientPub)
        let scope = ClientScope(workspaces: bootstrap.value.workspaces, capabilities: [.conversationControl])
        let enrollment = EnrollmentRequest(hostID: host.id, windowID: bootstrap.value.windowID, requestID: UUID().uuidString, clientID: clientID, clientPublicKey: clientPub, clientName: "Phone", clientKind: "iphone", nonce: UUID().uuidString, scope: scope, expiresAt: bootstrap.value.expiresAt)
        _ = try await authority.submit(crypto.sign(enrollment, domain: "enrollment-request", privateKey: key))
        try await authority.approve(requestID: enrollment.requestID, scope: scope)
        let cmux = AuthorizationRaceCmux(authority: authority, clientID: clientID, revokeDuringRefresh: revoke)
        let service = SessionService(cmux: cmux, home: dir, transcriptRoots: [])
        let router = BridgeRouter(service: service, authority: authority)
        let body = try JSONEncoder().encode(SendRequest(text: "Prompt"))
        let proof = RequestProof(epoch: authority.epoch, hostID: host.id, clientID: clientID, method: "POST", uri: "/v2/sessions/session/send", bodySHA256: crypto.digest(body), nonce: UUID().uuidString, timestamp: 1000)
        let header = "CmuxV2 " + (try JSONEncoder().encode(crypto.sign(proof, domain: "request", privateKey: key))).base64EncodedString()
        let result = await router.respond(method: "POST", uri: proof.uri, authorization: header, body: body)
        return (result.0, await cmux.sends, try await authority.enrolledClients()[0].revoked)
    }
    @Test func movedSessionMustBeDeniedBeforeWrite() async throws {
        let (status, sends, _) = try await exercise(revoke: false)
        #expect(status == 409)
        #expect(sends == 0)
    }
    @Test func revokedDeviceMustBeDeniedBeforeWrite() async throws {
        let (status, sends, revoked) = try await exercise(revoke: true)
        #expect(revoked)
        #expect(status == 401)
        #expect(sends == 0)
    }
}

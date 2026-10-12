import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

private actor BoundFeedFixture: CmuxControlling {
    let first = "11111111-1111-1111-1111-111111111111"
    let second = "33333333-3333-3333-3333-333333333333"
    var replies = 0
    var moved = false
    var gone = false
    var ended = false
    func removeSessions() { gone = true }
    func endSessions() { ended = true }
    var afterFeedRead: (@Sendable () async throws -> Void)?
    func setMoveOnRead() { moved = true }
    func setAfterRead(_ action: @escaping @Sendable () async throws -> Void) { afterFeedRead = action }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions": return .object(["sessions": .array([])])
        case "chat.sessions.dump":
            if gone { return .object(["sessions": .array([])]) }
            return .object(["sessions": .array([("owned", moved ? second : first), ("other", second)].map { id, workspace in .object(["session_id": .string(id), "agent": .string("claude"), "workspace_id": .string(workspace), "surface_id": .string("22222222-2222-2222-2222-222222222222"), "state": .string(ended ? "ended" : "idle")]) })])
        case "feed.list":
            if let afterFeedRead { self.afterFeedRead = nil; try await afterFeedRead() }
            return .object(["items": .array(["owned", "other", "unregistered"].map { id in .object(["id": .string(id), "request_id": .string(id), "workstream_id": .string("cmux-feed-v1:" + Data("claude".utf8).base64EncodedString() + ":" + Data(id.utf8).base64EncodedString()), "source": .string("claude"), "kind": .string("permissionRequest"), "status": .string("pending"), "tool_name": .string("Fixture tool")]) })])
        case "feed.permission.reply": replies += 1; return .object(["delivered": .bool(true)])
        default: return .object([:])
        }
    }
}
@Suite struct FeedBindingIntegrationTests {
    @Test(arguments: ["move", "end", "remove"])
    func authorizationAwaitCannotSendToReboundEndedOrRemovedWorkstream(_ change: String) async throws {
        let fixture = BoundFeedFixture()
        let service = SessionService(cmux: fixture, home: URL(fileURLWithPath: "/fixture/home"), transcriptRoots: [])
        let access = SessionAccess { _, workspace in
            #expect(workspace == "11111111-1111-1111-1111-111111111111")
            if change == "move" { await fixture.setMoveOnRead() }
            else if change == "end" { await fixture.endSessions() }
            else { await fixture.removeSessions() }
            _ = try await service.sessions()
        }
        do {
            _ = try await service.reply(requestID: "owned", body: .object(["operation_id": .string(UUID().uuidString), "kind": .string("permissionRequest"), "mode": .string("once")]), access: access)
            Issue.record("Expected the changed target to be denied")
        } catch { #expect((error as? BridgeError)?.code == "stale_binding") }
        #expect(await fixture.replies == 0)
    }
    @Test func realShapeFeedWithoutWorkspaceFieldIsScopedAndActionable() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let crypto = IdentityCryptography(), hostKey = IdentityCryptography().generatePrivateKey(), deviceKey = IdentityCryptography().generatePrivateKey()
        let pub = try crypto.publicKey(privateKey: hostKey)
        let host = HostIdentity(id: try crypto.identityID(publicKey: pub), publicKey: pub, certificateSHA256: String(repeating: "a", count: 64), name: "Fixture")
        let authority = try ConnectionAuthority(host: host, privateKey: hostKey, registryFile: dir.appendingPathComponent("clients.json"), now: { 1000 })
        let workspace = "11111111-1111-1111-1111-111111111111"
        let bootstrap = try await authority.open(endpoint: BridgeEndpoint(host: "127.0.0.1", port: 7740), workspaces: [workspace])
        let devicePub = try crypto.publicKey(privateKey: deviceKey), deviceID = try crypto.identityID(publicKey: devicePub)
        // Feed-only grant deliberately has no conversationRead; session discovery stays internal.
        let scope = ClientScope(workspaces: [workspace], capabilities: [.workspaceRead, .feedRead, .feedReply])
        let enrollment = EnrollmentRequest(hostID: host.id, windowID: bootstrap.value.windowID, requestID: UUID().uuidString, clientID: deviceID, clientPublicKey: devicePub, clientName: "Fixture", clientKind: "iphone", nonce: UUID().uuidString, scope: scope, expiresAt: bootstrap.value.expiresAt)
        _ = try await authority.submit(crypto.sign(enrollment, domain: "enrollment-request", privateKey: deviceKey))
        try await authority.approve(requestID: enrollment.requestID, scope: scope)
        let fixture = BoundFeedFixture()
        let service = SessionService(cmux: fixture, home: dir, transcriptRoots: [])
        let router = BridgeRouter(service: service, authority: authority)
        func request(_ method: String, _ uri: String, body: Data = Data()) async throws -> (Int, Data) {
            let proof = RequestProof(epoch: authority.epoch, hostID: host.id, clientID: deviceID, method: method, uri: uri, bodySHA256: crypto.digest(body), nonce: UUID().uuidString, timestamp: 1000)
            let header = "CmuxV2 " + (try JSONEncoder().encode(crypto.sign(proof, domain: "request", privateKey: deviceKey))).base64EncodedString()
            return await router.respond(method: method, uri: uri, authorization: header, body: body)
        }
        let response = try await request("GET", "/v2/feed")
        #expect(response.0 == 200)
        let value = try JSONDecoder().decode(JSONValue.self, from: response.1)
        #expect(value["items"].array?.count == 1)
        #expect(value["items"].array?.first?["request_id"].string == "owned")
        #expect(value["items"].array?.first?["workspace_id"].string == workspace)
        func decision() throws -> Data { try JSONEncoder().encode(JSONValue.object(["operation_id": .string(UUID().uuidString), "kind": .string("permissionRequest"), "mode": .string("all")])) }
        let data = try decision()
        #expect(try await request("POST", "/v2/feed/owned/reply", body: data).0 == 200)
        #expect(try await request("POST", "/v2/feed/other/reply", body: decision()).0 == 403)
        #expect(try await request("POST", "/v2/feed/unregistered/reply", body: decision()).0 == 403)
        #expect(await fixture.replies == 1)
        await fixture.setMoveOnRead()
        let movedResponse = try await request("GET", "/v2/feed")
        #expect(movedResponse.0 == 200)
        #expect(try JSONDecoder().decode(JSONValue.self, from: movedResponse.1)["items"].array?.isEmpty == true)
        #expect(try await request("POST", "/v2/feed/owned/reply", body: decision()).0 == 403)
        // A saved receipt remains readable under its original approved scope;
        // this returns metadata and does not reply to the moved target again.
        #expect(try await request("POST", "/v2/feed/owned/reply", body: data).0 == 200)
        #expect(await fixture.replies == 1)
        await fixture.setAfterRead { try await authority.revoke(clientID: deviceID) }
        // Grant was valid at router entry, but revoked while the backend snapshot awaited.
        #expect(try await request("GET", "/v2/feed").0 == 401)
        #expect(try await request("POST", "/v2/feed/owned/reply", body: data).0 == 401)
        #expect(await fixture.replies == 1)
    }
}

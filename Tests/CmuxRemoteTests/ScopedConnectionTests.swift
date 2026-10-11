import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteClient

private actor ScopedCmux: CmuxControlling {
    let first = "11111111-1111-1111-1111-111111111111"
    let second = "33333333-3333-3333-3333-333333333333"
    let transcript: String
    let project: String
    var sends = 0
    init(transcript: String, project: String) { self.transcript = transcript; self.project = project }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions": return .object(["sessions": .array(["first", "second"].map { .object(["session_id": .string($0), "agent": .string("claude"), "title": .string($0), "cwd": .string(project), "file": .string(transcript)]) })])
        case "chat.sessions.dump": return .object(["sessions": .array([( "first", first ), ( "second", second )].map { id, workspace in .object(["session_id": .string(id), "agent": .string("claude"), "workspace_id": .string(workspace), "surface_id": .string("22222222-2222-2222-2222-222222222222"), "state": .string("idle")]) })])
        case "workspace.list": return .object(["workspaces": .array([first, second].map { .object(["id": .string($0), "title": .string($0)]) })])
        case "surface.input_state": return .object(["agent": .bool(true), "workspace_id": params["workspace_id"] ?? .null, "surface_id": params["surface_id"] ?? .null, "blocks_typing": .bool(false)])
        case "mobile.chat.send": sends += 1; return .object(["submitted": .bool(true)])
        case "feed.list": return .object(["items": .array([first, second].map { .object(["workspace_id": .string($0), "request_id": .string($0), "status": .string("pending"), "kind": .string("permissionRequest")]) })])
        default: return .object([:])
        }
    }
}

@Suite struct ScopedConnectionTests {
    @Test func iphoneAndMacEnrollIndependentlyOverTLSWithLocalOwnerApprovalAndRevocation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = BridgeState(directory: directory); try state.initialize(); let authority = try state.authority(name: "Test host")
        let transcript = directory.appendingPathComponent("history.jsonl")
        try Data((#"{"type":"assistant","uuid":"ready","message":{"content":[{"type":"text","text":"Ready"}]}}"# + "\n").utf8).write(to: transcript)
        let cmux = ScopedCmux(transcript: transcript.path, project: directory.path)
        let service = SessionService(cmux: cmux, home: directory.appendingPathComponent("home"), transcriptRoots: [directory])
        let ownerReady = AsyncThrowingStream<Void, any Error>.makeStream()
        let owner = Task {
            do { try await OwnerControlServer().run(path: directory.appendingPathComponent("owner.sock").path, authority: authority, service: service, onListening: { ownerReady.continuation.yield(()); ownerReady.continuation.finish() }) }
            catch { ownerReady.continuation.finish(throwing: error); throw error }
        }
        defer { owner.cancel() }
        var ready = ownerReady.stream.makeAsyncIterator(); _ = try await ready.next()
        let ownerClient = UnixSocketClient(path: directory.appendingPathComponent("owner.sock").path)
        let listening = AsyncThrowingStream<Int, any Error>.makeStream()
        let server = Task {
            do { try await HTTPServer().run(host: "127.0.0.1", port: 0, certificate: state.certificate, key: state.key, router: BridgeRouter(service: service, authority: authority), onListening: { listening.continuation.yield($0); listening.continuation.finish() }) }
            catch { listening.continuation.finish(throwing: error); throw error }
        }
        defer { server.cancel() }
        var iterator = listening.stream.makeAsyncIterator(); let port = try #require(await iterator.next())
        let raw = try await ownerClient.request("enrollment.open", params: ["host": .string("127.0.0.1"), "port": .number(Double(port))])
        let bootstrap = try JSONDecoder().decode(SignedValue<EnrollmentBootstrap>.self, from: JSONEncoder().encode(raw))
        let phone = try EnrollmentClient(bootstrap: bootstrap, privateKey: IdentityCryptography().generatePrivateKey(), name: "Phone", kind: "iphone")
        let mac = try EnrollmentClient(bootstrap: bootstrap, privateKey: IdentityCryptography().generatePrivateKey(), name: "Mac", kind: "mac")
        defer { phone.close(); mac.close() }
        #expect(try await phone.submit().state == "pending"); #expect(try await mac.submit().state == "pending")
        let pending = try await ownerClient.request("enrollment.pending")
        #expect(pending.array?.count == 2)
        let first = await cmux.first; let second = await cmux.second
        let view = ClientScope(workspaces: [first], capabilities: [.workspaceRead, .conversationRead])
        let control = ClientScope(workspaces: [second], capabilities: ClientCapability.allCases)
        for (request, scope) in [(phone.request, view), (mac.request, control)] {
            _ = try await ownerClient.request("enrollment.approve", params: ["request_id": .string(request.value.requestID), "scope": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(scope))])
        }
        let phoneConnection = try phone.connection(from: await phone.status())
        let macConnection = try mac.connection(from: await mac.status())
        let phoneClient = try RemoteClient(connection: phoneConnection); let macClient = try RemoteClient(connection: macConnection)
        defer { phoneClient.close(); macClient.close() }
        #expect(!phoneClient.canControlConversations); #expect(macClient.canControlConversations)
        #expect(try await phoneClient.get("/v1/sessions", as: [SessionDescriptor].self).map(\.id) == ["first"])
        #expect(try await macClient.get("/v1/sessions", as: [SessionDescriptor].self).map(\.id) == ["second"])
        let history = try await phoneClient.get("/v1/sessions/first/history", as: ConversationSnapshot.self); #expect(history.messages.count == 1)
        for path in ["/v1/sessions/second/history", "/v1/sessions/first/file"] {
            do { _ = try await phoneClient.get(path, query: ["path": "history.jsonl"], as: JSONValue.self); Issue.record("Expected workspace/capability denial") }
            catch { #expect((error as? BridgeError)?.code == "scope_denied") }
        }
        do { _ = try await phoneClient.post("/v1/sessions/first/send", body: SendRequest(text: "Test"), as: MutationReceipt.self); Issue.record("Expected viewing-only denial") }
        catch { #expect((error as? BridgeError)?.code == "scope_denied") }
        #expect(await cmux.sends == 0)
        _ = try await macClient.post("/v1/sessions/second/send", body: SendRequest(text: "Test"), as: MutationReceipt.self)
        #expect(await cmux.sends == 1)
        let feed = try await macClient.get("/v1/feed", as: JSONValue.self); #expect(feed["items"].array?.count == 1)
        _ = try await ownerClient.request("clients.revoke", params: ["client_id": .string(phoneConnection.grant.value.clientID)])
        do { _ = try await phoneClient.get("/v1/sessions", as: [SessionDescriptor].self); Issue.record("Expected revoked device rejection") }
        catch { #expect((error as? BridgeError)?.code == "unauthorized") }
        #expect(try await macClient.get("/v1/sessions", as: [SessionDescriptor].self).count == 1)
        let legacy = RemoteClient(pairing: try state.pairing(host: "127.0.0.1", port: port)); defer { legacy.close() }
        do { _ = try await legacy.get("/v1/status", as: JSONValue.self); Issue.record("Legacy is not enabled implicitly") }
        catch { #expect((error as? BridgeError)?.code == "unauthorized") }
        server.cancel(); owner.cancel(); try await server.value; try await owner.value
    }
    @Test func savedTrustAllowsEndpointChangesButRejectsDifferentIdentitiesOrCertificates() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString); defer { try? FileManager.default.removeItem(at: directory) }
        let state = BridgeState(directory: directory); try state.initialize(); let authority = try state.authority(name: "Host")
        let workspace = "11111111-1111-1111-1111-111111111111"
        let bootstrap = try await authority.open(endpoint: BridgeEndpoint(host: "192.168.1.2", port: 7740), workspaces: [workspace])
        let client = try EnrollmentClient(bootstrap: bootstrap, privateKey: IdentityCryptography().generatePrivateKey(), name: "Mac", kind: "mac"); defer { client.close() }
        _ = try await authority.submit(client.request); try await authority.approve(requestID: client.request.value.requestID, scope: client.request.value.scope)
        let connection = try client.connection(from: await authority.status(client.request).value)
        let moved = try connection.relocated(to: BridgeEndpoint(host: "192.168.1.99", port: 8888), advertisedHost: connection.host)
        #expect(moved.grant.value.clientID == connection.grant.value.clientID); #expect(moved.endpoint.host == "192.168.1.99")
        var changed = connection.host; changed.certificateSHA256 = String(repeating: "0", count: 64)
        do { _ = try connection.relocated(to: moved.endpoint, advertisedHost: changed); Issue.record("Expected certificate continuity rejection") }
        catch { #expect((error as? BridgeError)?.code == "host_changed") }
        let restarted = try state.authority(name: "Renamed host")
        #expect(restarted.host.id == authority.host.id); #expect(try await restarted.enrolledClients().count == 1)
        do { _ = try await restarted.bootstrap(); Issue.record("Restart must not reopen enrollment") }
        catch { #expect((error as? BridgeError)?.code == "enrollment_closed") }
    }
}

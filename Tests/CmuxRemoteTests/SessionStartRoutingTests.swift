import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

private actor RoutedLaunchCmux: CmuxControlling {
    let workspace = "11111111-1111-1111-1111-111111111111"
    let root: String
    var creates = 0
    init(root: String) { self.root = root }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "workspace.list": return .object(["workspaces": .array([.object(["id": .string(workspace), "current_directory": .string(root)])])])
        case "surface.create": creates += 1; return .object(["surface_id": .string("22222222-2222-2222-2222-222222222222")])
        default: return .object([:])
        }
    }
}

@Suite struct SessionStartRoutingTests {
    private struct Device { let id: String; let key: Data }
    private func signed(_ method: String, _ uri: String, body: Data, device: Device, authority: ConnectionAuthority) async throws -> String {
        let crypto = IdentityCryptography()
        let proof = RequestProof(epoch: authority.epoch, hostID: authority.host.id, clientID: device.id, method: method, uri: uri, bodySHA256: crypto.digest(body), nonce: UUID().uuidString, timestamp: 1000)
        return "CmuxV2 " + (try JSONEncoder().encode(crypto.sign(proof, domain: "request", privateKey: device.key))).base64EncodedString()
    }
    private func enroll(_ requested: [ClientCapability], approved: [ClientCapability], authority: ConnectionAuthority, workspace: String) async throws -> Device {
        let crypto = IdentityCryptography(), key = crypto.generatePrivateKey()
        let bootstrap = try await authority.open(endpoint: BridgeEndpoint(host: "127.0.0.1", port: 7740), workspaces: [workspace])
        let publicKey = try crypto.publicKey(privateKey: key), id = try crypto.identityID(publicKey: publicKey)
        let request = EnrollmentRequest(hostID: authority.host.id, windowID: bootstrap.value.windowID, requestID: UUID().uuidString, clientID: id, clientPublicKey: publicKey, clientName: "Phone", clientKind: "iphone", nonce: UUID().uuidString, scope: ClientScope(workspaces: [workspace], capabilities: requested), expiresAt: bootstrap.value.expiresAt)
        _ = try await authority.submit(crypto.sign(request, domain: "enrollment-request", privateKey: key))
        try await authority.approve(requestID: request.requestID, scope: ClientScope(workspaces: [workspace], capabilities: approved))
        return Device(id: id, key: key)
    }

    @Test func onlyAGrantWithStartCanListFoldersAndOpenATerminal() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        let root = dir.appendingPathComponent("projects/app")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let crypto = IdentityCryptography(), hostKey = crypto.generatePrivateKey(), hostPublic = try crypto.publicKey(privateKey: hostKey)
        let host = HostIdentity(id: try crypto.identityID(publicKey: hostPublic), publicKey: hostPublic, certificateSHA256: String(repeating: "a", count: 64), name: "Host")
        let authority = try ConnectionAuthority(host: host, privateKey: hostKey, registryFile: dir.appendingPathComponent("clients.json"), now: { 1000 })
        let cmux = RoutedLaunchCmux(root: root.path)
        let service = SessionService(cmux: cmux, home: dir, transcriptRoots: [])
        let router = BridgeRouter(service: service, authority: authority, launcher: SessionLauncher(cmux: cmux, home: dir, mutations: MutationLedger(), sessions: { [] }))
        let workspace = cmux.workspace
        let control: [ClientCapability] = [.workspaceRead, .conversationRead, .conversationControl]
        let withheld = try await enroll(control + [.conversationStart], approved: control, authority: authority, workspace: workspace)
        let allowed = try await enroll(control + [.conversationStart], approved: control + [.conversationStart], authority: authority, workspace: workspace)

        let listURI = "/v2/workspaces/\(workspace)/directories"
        let denied = await router.respond(method: "GET", uri: listURI, authorization: try await signed("GET", listURI, body: Data(), device: withheld, authority: authority), body: Data())
        #expect(denied.0 == 403)
        let listed = await router.respond(method: "GET", uri: listURI, authorization: try await signed("GET", listURI, body: Data(), device: allowed, authority: authority), body: Data())
        #expect(listed.0 == 200)
        let roots = try JSONDecoder().decode([LaunchDirectory].self, from: listed.1)
        #expect(roots.count == 1)

        let startURI = "/v2/workspaces/\(workspace)/sessions"
        let body = try JSONEncoder().encode(StartSessionRequest(rootID: roots[0].id, agent: .claude))
        let refused = await router.respond(method: "POST", uri: startURI, authorization: try await signed("POST", startURI, body: body, device: withheld, authority: authority), body: body)
        #expect(refused.0 == 403)
        #expect(await cmux.creates == 0)
        let started = await router.respond(method: "POST", uri: startURI, authorization: try await signed("POST", startURI, body: body, device: allowed, authority: authority), body: body)
        #expect(started.0 == 200)
        #expect(try JSONDecoder().decode(StartSessionReceipt.self, from: started.1).surfaceID == "22222222-2222-2222-2222-222222222222")
        #expect(await cmux.creates == 1)
    }

    @Test func approvalCannotAddStartToADeviceThatDidNotAskForIt() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let crypto = IdentityCryptography(), hostKey = crypto.generatePrivateKey(), hostPublic = try crypto.publicKey(privateKey: hostKey)
        let host = HostIdentity(id: try crypto.identityID(publicKey: hostPublic), publicKey: hostPublic, certificateSHA256: String(repeating: "a", count: 64), name: "Host")
        let authority = try ConnectionAuthority(host: host, privateKey: hostKey, registryFile: dir.appendingPathComponent("clients.json"), now: { 1000 })
        let workspace = "11111111-1111-1111-1111-111111111111"
        await #expect(throws: BridgeError.self) {
            _ = try await enroll([.conversationRead, .conversationControl], approved: [.conversationRead, .conversationControl, .conversationStart], authority: authority, workspace: workspace)
        }
    }
}

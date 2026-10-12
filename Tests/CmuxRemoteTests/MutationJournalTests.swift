import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

private actor JournalCmux: CmuxControlling {
    var sends = 0
    var interrupts = 0
    var replies = 0
    var resourcesGone = false
    func removeResources() { resourcesGone = true }
    let fail: Bool
    let workspace: String
    let afterSend: @Sendable () throws -> Void
    init(fail: Bool = false, workspace: String = "workspace", afterSend: @escaping @Sendable () throws -> Void = {}) { self.fail = fail; self.workspace = workspace; self.afterSend = afterSend }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "vault.sessions": return .object(["sessions": .array(resourcesGone ? [] : [.object(["session_id": .string("session"), "agent": .string("claude")])])])
        case "chat.sessions.dump": return .object(["sessions": .array(resourcesGone ? [] : [.object(["session_id": .string("session"), "agent": .string("claude"), "workspace_id": .string(workspace), "surface_id": .string("surface"), "state": .string("idle")])])])
        case "surface.input_state": return .object(["agent": .bool(true), "workspace_id": .string(workspace), "surface_id": .string("surface"), "blocks_typing": .bool(false)])
        case "feed.list": return .object(["items": .array(resourcesGone ? [] : [.object(["request_id": .string("request"), "kind": .string("permissionRequest"), "source": .string("claude"), "status": .string(replies == 0 ? "pending" : "resolved"), "workspace_id": .string(workspace)])])])
        case "mobile.chat.send": sends += 1; try afterSend(); if fail { throw BridgeError("outcome_unknown", "Lost response", status: 504) }
        case "mobile.chat.interrupt": interrupts += 1
        case "feed.permission.reply": replies += 1
        default: break
        }
        return .object(["accepted": .bool(true)])
    }
}

@Suite struct MutationJournalTests {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cmux-journal-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        return root
    }
    private func service(_ cmux: JournalCmux, _ root: URL, capacity: Int = 4096) throws -> SessionService {
        SessionService(cmux: cmux, home: root, transcriptRoots: [], journal: try MutationJournal(file: root.appendingPathComponent("operations.json"), capacity: capacity))
    }
    private func expectCode(_ code: String, operation: () async throws -> Void) async {
        do { try await operation(); Issue.record("Expected \(code)") }
        catch { #expect((error as? BridgeError)?.code == code) }
    }
    @Test func confirmedSendSurvivesServiceRestartWithoutSavingItsPrompt() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let cmux = JournalCmux(); let request = SendRequest(text: "SECRET_PROMPT_NOT_STORED_41")
        _ = try await service(cmux, root).send(id: "session", request: request)
        let restored = try service(cmux, root)
        let receipt = try await restored.send(id: "session", request: request)
        #expect(receipt.accepted && receipt.operationID == request.operationID)
        #expect(await cmux.sends == 1)
        #expect(try await restored.operationStatus(id: request.operationID).state == .accepted)
        let file = root.appendingPathComponent("operations.json")
        #expect(!(try String(contentsOf: file, encoding: .utf8)).contains(request.text))
        let mode = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        #expect(mode?.intValue == 0o600)
    }
    @Test func lostReceiptSurvivesRestartAndNeverRepeatsTheSend() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let cmux = JournalCmux(fail: true); let request = SendRequest(text: "Unknown")
        let first = try service(cmux, root)
        await expectCode("outcome_unknown") { _ = try await first.send(id: "session", request: request) }
        let restored = try service(cmux, root)
        await expectCode("outcome_unknown") { _ = try await restored.send(id: "session", request: request) }
        #expect(await cmux.sends == 1)
        #expect(try await restored.operationStatus(id: request.operationID).state == .outcomeUnknown)
    }
    @Test func preparedRecordAfterCrashIsUncertainEvenWithoutRecordedDispatch() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let request = SendRequest(text: "Prepared")
        var journal = try MutationJournal(file: root.appendingPathComponent("operations.json"))
        try journal.begin(id: request.operationID, signature: "send:session:Prepared", principal: "legacy", resource: "session:session", workspace: "workspace", capability: .conversationControl)
        let cmux = JournalCmux(); let restored = try service(cmux, root)
        await expectCode("outcome_unknown") { _ = try await restored.send(id: "session", request: request) }
        #expect(await cmux.sends == 0)
    }
    @Test func finalDiskFailureReportsUnknownAndPreparedRecordStillBlocksReplay() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("operations.json")
        let cmux = JournalCmux(afterSend: { try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path) })
        let request = SendRequest(text: "Delivered before disk failure"); let first = try service(cmux, root)
        await expectCode("outcome_unknown") { _ = try await first.send(id: "session", request: request) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        let restored = try service(cmux, root)
        await expectCode("outcome_unknown") { _ = try await restored.send(id: "session", request: request) }
        #expect(await cmux.sends == 1)
    }
    @Test func failedPreparationNeverDispatchesToCmux() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let cmux = JournalCmux(); let first = try service(cmux, root)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.path)
        await expectCode("journal_unavailable") { _ = try await first.send(id: "session", request: SendRequest(text: "Not delivered")) }
        #expect(await cmux.sends == 0)
    }
    @Test func corruptOrLinkedJournalFailsClosed() throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("operations.json")
        try Data("not JSON".utf8).write(to: file); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        #expect(throws: BridgeError.self) { _ = try MutationJournal(file: file) }
        let target = root.appendingPathComponent("external.json"); try FileManager.default.moveItem(at: file, to: target)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
        #expect(throws: BridgeError.self) { _ = try MutationJournal(file: file) }
    }
    @Test func capacityNeverEvictsTheEarlierReceipt() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let cmux = JournalCmux(); let first = try service(cmux, root, capacity: 1); let request = SendRequest(text: "First")
        _ = try await first.send(id: "session", request: request)
        await expectCode("receipt_capacity") { _ = try await first.send(id: "session", request: SendRequest(text: "Second")) }
        let restored = try service(cmux, root, capacity: 1)
        #expect(try await restored.send(id: "session", request: request).accepted)
        #expect(await cmux.sends == 1)
    }
    @Test func persistedReceiptIsBoundToDeviceAndCurrentOriginalScope() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let cmux = JournalCmux(); let request = SendRequest(text: "Owned")
        let owner = SessionAccess(principalID: "device-a") { _, workspace in #expect(workspace == "workspace") }
        _ = try await service(cmux, root).send(id: "session", request: request, access: owner)
        let restored = try service(cmux, root)
        let other = SessionAccess(principalID: "device-b") { _, _ in }
        await expectCode("scope_denied") { _ = try await restored.operationStatus(id: request.operationID, access: other) }
        await expectCode("scope_denied") { _ = try await restored.send(id: "session", request: request, access: other) }
        let revoked = SessionAccess(principalID: "device-a") { _, _ in throw BridgeError("scope_denied", "Revoked", status: 403) }
        await expectCode("scope_denied") { _ = try await restored.operationStatus(id: request.operationID, access: revoked) }
        await expectCode("scope_denied") { _ = try await restored.send(id: "session", request: request, access: revoked) }
        #expect(await cmux.sends == 1)
    }
    @Test func changedInputCannotReuseAConfirmedOperationAfterRestart() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let cmux = JournalCmux(); let request = SendRequest(text: "First")
        _ = try await service(cmux, root).send(id: "session", request: request)
        let restored = try service(cmux, root)
        await expectCode("operation_conflict") { _ = try await restored.send(id: "session", request: SendRequest(text: "Changed", operationID: request.operationID)) }
        #expect(await cmux.sends == 1)
    }
    @Test func stopAndResolvedFeedDecisionsAlsoSurviveRestart() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let cmux = JournalCmux(); let stop = InterruptRequest(hard: true)
        let decision: JSONValue = .object(["operation_id": .string(UUID().uuidString), "kind": .string("permissionRequest"), "mode": .string("once")])
        let first = try service(cmux, root)
        _ = try await first.interrupt(id: "session", request: stop)
        _ = try await first.reply(requestID: "request", body: decision)
        let restored = try service(cmux, root)
        #expect(try await restored.interrupt(id: "session", request: stop).accepted)
        #expect(try await restored.reply(requestID: "request", body: decision).accepted)
        #expect(await cmux.interrupts == 1)
        #expect(await cmux.replies == 1)
    }
    @Test func signedReceiptRouteRestoresAcrossEpochsAndRejectsOtherOrRevokedDevices() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at: root) }
        let workspace = "11111111-1111-1111-1111-111111111111"
        let crypto = IdentityCryptography(); let hostKey = crypto.generatePrivateKey()
        let publicKey = try crypto.publicKey(privateKey: hostKey)
        let host = HostIdentity(id: try crypto.identityID(publicKey: publicKey), publicKey: publicKey, certificateSHA256: String(repeating: "a", count: 64), name: "Journal fixture")
        let registry = root.appendingPathComponent("clients.json")
        let authority = try ConnectionAuthority(host: host, privateKey: hostKey, registryFile: registry, now: { 1000 })
        let bootstrap = try await authority.open(endpoint: BridgeEndpoint(host: "127.0.0.1", port: 7740), workspaces: [workspace])
        let scope = ClientScope(workspaces: [workspace], capabilities: [.conversationRead, .conversationControl, .feedRead, .feedReply])
        func enroll(_ key: Data) async throws -> String {
            let pub = try crypto.publicKey(privateKey: key), id = try crypto.identityID(publicKey: pub)
            let request = EnrollmentRequest(hostID: host.id, windowID: bootstrap.value.windowID, requestID: UUID().uuidString, clientID: id, clientPublicKey: pub, clientName: "Fixture", clientKind: "iphone", nonce: UUID().uuidString, scope: scope, expiresAt: bootstrap.value.expiresAt)
            _ = try await authority.submit(crypto.sign(request, domain: "enrollment-request", privateKey: key))
            try await authority.approve(requestID: request.requestID, scope: scope)
            return id
        }
        let ownerKey = crypto.generatePrivateKey(), otherKey = crypto.generatePrivateKey()
        let ownerID = try await enroll(ownerKey), otherID = try await enroll(otherKey)
        let cmux = JournalCmux(workspace: workspace)
        let firstRouter = BridgeRouter(service: try service(cmux, root), authority: authority)
        func call(_ router: BridgeRouter, _ auth: ConnectionAuthority, _ id: String, _ key: Data, _ method: String, _ uri: String, _ body: Data = Data()) async throws -> (Int, Data) {
            let proof = RequestProof(epoch: auth.epoch, hostID: host.id, clientID: id, method: method, uri: uri, bodySHA256: crypto.digest(body), nonce: UUID().uuidString, timestamp: 1000)
            let header = "CmuxV2 " + (try JSONEncoder().encode(crypto.sign(proof, domain: "request", privateKey: key))).base64EncodedString()
            return await router.respond(method: method, uri: uri, authorization: header, body: body)
        }
        let request = SendRequest(text: "Receipt fixture")
        let body = try JSONEncoder().encode(request)
        #expect(try await call(firstRouter, authority, ownerID, ownerKey, "POST", "/v2/sessions/session/send", body).0 == 200)
        let stopBody = try JSONEncoder().encode(InterruptRequest())
        let decisionBody = try JSONEncoder().encode(JSONValue.object(["operation_id": .string(UUID().uuidString), "kind": .string("permissionRequest"), "mode": .string("once")]))
        #expect(try await call(firstRouter, authority, ownerID, ownerKey, "POST", "/v2/sessions/session/interrupt", stopBody).0 == 200)
        #expect(try await call(firstRouter, authority, ownerID, ownerKey, "POST", "/v2/feed/request/reply", decisionBody).0 == 200)
        let restarted = try ConnectionAuthority(host: host, privateKey: hostKey, registryFile: registry, now: { 1000 })
        #expect(restarted.epoch != authority.epoch)
        let router = BridgeRouter(service: try service(cmux, root), authority: restarted)
        let uri = "/v2/operations/" + request.operationID.uuidString
        let result = try await call(router, restarted, ownerID, ownerKey, "GET", uri)
        #expect(result.0 == 200)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        #expect(try decoder.decode(OperationStatus.self, from: result.1).state == .accepted)
        #expect(try await call(router, restarted, ownerID, ownerKey, "POST", "/v2/sessions/session/send", body).0 == 200)
        await cmux.removeResources()
        #expect(try await call(router, restarted, ownerID, ownerKey, "GET", uri).0 == 200)
        #expect(try await call(router, restarted, ownerID, ownerKey, "POST", "/v2/sessions/session/send", body).0 == 200)
        #expect(try await call(router, restarted, ownerID, ownerKey, "POST", "/v2/sessions/session/interrupt", stopBody).0 == 200)
        #expect(try await call(router, restarted, ownerID, ownerKey, "POST", "/v2/feed/request/reply", decisionBody).0 == 200)
        let freshBody = try JSONEncoder().encode(SendRequest(text: "Never dispatch without the resource"))
        #expect(try await call(router, restarted, ownerID, ownerKey, "POST", "/v2/sessions/session/send", freshBody).0 != 200)
        #expect(try await call(router, restarted, otherID, otherKey, "GET", uri).0 == 403)
        #expect(try await call(router, restarted, ownerID, ownerKey, "GET", "/v2/operations/invalid").0 == 400)
        #expect(try await call(router, restarted, ownerID, ownerKey, "GET", "/v2/operations/" + UUID().uuidString).0 == 404)
        try await restarted.revoke(clientID: ownerID)
        #expect(try await call(router, restarted, ownerID, ownerKey, "GET", uri).0 == 401)
        #expect(try await call(router, restarted, ownerID, ownerKey, "POST", "/v2/sessions/session/send", body).0 == 401)
        #expect(await cmux.sends == 1)
        #expect(await cmux.interrupts == 1)
        #expect(await cmux.replies == 1)
    }
}

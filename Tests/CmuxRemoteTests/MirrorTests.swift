import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteClient
import CmuxRemoteMac
import CmuxTerminalReplay

private actor MirrorTestCmux: CmuxControlling {
    let workspaceID = "11111111-1111-1111-1111-111111111111"
    let surfaceID = "22222222-2222-2222-2222-222222222222"
    var epoch = "producer-1"
    var inputs = 0
    var failInput = false
    var cellText = "Hello 👩‍💻"
    var calls = 0
    var lifecycle = "working"
    var replays = 0
    func hibernate() { lifecycle = "hibernated" }
    func setEpoch(_ value: String) { epoch = value }
    func setFailure() { failInput = true }
    func setText(_ value: String) { cellText = value }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        calls += 1
        switch method {
        case "surface.input_state": return .object(["terminal": .bool(true), "lifecycle": .string(lifecycle)])
        case "surface.list": return .object(["workspace_id": .string(workspaceID), "surfaces": .array([.object(["id": .string(surfaceID), "type": .string("terminal")])])])
        case "terminal.replay":
            replays += 1
            let frame = try MobileTerminalRenderGridFrame(surfaceID: surfaceID, stateSeq: 0, renderEpoch: epoch, renderRevision: 1,
                columns: 80, rows: 24, rowSpans: [.init(row: 0, column: 0, styleID: 0, text: cellText)], anchor: .screen)
            return .object(["workspace_id": .string(workspaceID), "surface_id": .string(surfaceID),
                "render_grid": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(frame))])
        case "mobile.terminal.input": inputs += 1; if failInput { throw BridgeError("socket_unavailable", "fixture") }; return .object(["accepted": .bool(true)])
        default: return .object([:])
        }
    }
}

private actor MirrorTestRemote: MirrorRemoteControlling {
    let workspaceID = "11111111-1111-1111-1111-111111111111"
    let first = "22222222-2222-2222-2222-222222222222"
    let second = "33333333-3333-3333-3333-333333333333"
    var epoch = "producer-1"
    var inputs = 0
    var presentation = Data("fixture".utf8)
    func setPresentation(_ bytes: Data) { presentation = bytes }
    func changeEpoch() { epoch = "producer-2" }
    func workspace(_ id: String) async throws -> MirrorWorkspaceSnapshot {
        .init(id: workspaceID, title: "Agents", layout: .object(["direction": .string("horizontal"), "split": .number(0.6), "children": .array([
            .object(["pane": .object(["id": .string(first)])]), .object(["pane": .object(["id": .string(second)])])])]),
            surfaces: [.init(id: first, paneID: first, title: "Claude"), .init(id: second, paneID: second, title: "Codex")])
    }
    func replay(workspaceID: String, surfaceID: String) async throws -> MirrorTerminalSnapshot {
        .init(workspaceID: workspaceID, surfaceID: surfaceID, runtimeEpoch: epoch, columns: 80, rows: 24, bytes: presentation)
    }
    func input(workspaceID: String, surfaceID: String, request: MirrorInputRequest) async throws -> MutationReceipt {
        inputs += 1; return .init(operationID: request.operationID, accepted: true)
    }
}

private actor MirrorTestLocal: CmuxControlling {
    var methods: [String] = []
    var commands: [String] = []
    var surfaces: [String] = []
    var titles: [String: String] = [:]
    let workspaceID = "44444444-4444-4444-4444-444444444444"
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        methods.append(method)
        switch method {
        case "surface.action":
            if params["action"]?.string == "rename", let id = params["surface_id"]?.string, let title = params["title"]?.string { titles[id] = title }
            return .object([:])
        case "workspace.create", "surface.split", "surface.create":
            commands.append(params["initial_command"]?.string ?? "")
            let id = UUID().uuidString; surfaces.append(id)
            return .object(["workspace_id": .string(workspaceID), "surface_id": .string(id)])
        case "workspace.list": return .object(["workspaces": .array([.object(["id": .string(workspaceID)])])])
        case "surface.list": return .object(["surfaces": .array(surfaces.map { .object(["id": .string($0), "pane_id": .string($0)]) })])
        default: return .object([:])
        }
    }
}

@Suite struct MirrorTests {
    @Test func existingMirrorPublishesOlderPeersOnlyAfterFinalPaint() async throws {
        let local = MirrorTestLocal(), remote = MirrorTestRemote()
        let coordinator = WorkspaceMirrorCoordinator(local: local, executable: URL(fileURLWithPath: "/tmp/viewer"), stateDirectory: URL(fileURLWithPath: "/tmp/state"))
        let host = HostIdentity(id: "host", publicKey: "", certificateSHA256: "", name: "Remote")
        _ = try await coordinator.create(host: host, workspaceID: remote.workspaceID, remote: remote)
        let view = try #require(await coordinator.list().first)
        await remote.setPresentation(Data("\u{1B}[?2026h\u{1B}[2J\u{1B}[?2026lSTABLE_HEADER".utf8))
        let snapshot = try await coordinator.replay(view.id)
        let publication = try #require(snapshot.bytes.range(of: Data("\u{1B}[?2026l".utf8)))
        let content = try #require(snapshot.bytes.range(of: Data("STABLE_HEADER".utf8)))
        #expect(content.upperBound <= publication.lowerBound)
        #expect(publication.upperBound == snapshot.bytes.endIndex)
        #expect(snapshot.runtimeEpoch == view.runtimeEpoch)
        #expect(await local.commands.count == 2, "Presentation updates must keep the existing viewers")
    }

    @Test func initialMirrorPreservesSourceTerminalNames() async throws {
        let local = MirrorTestLocal(), remote = MirrorTestRemote()
        let coordinator = WorkspaceMirrorCoordinator(local: local, executable: URL(fileURLWithPath: "/tmp/viewer"), stateDirectory: URL(fileURLWithPath: "/tmp/state"))
        let host = HostIdentity(id: "host", publicKey: "", certificateSHA256: "", name: "Remote")
        _ = try await coordinator.create(host: host, workspaceID: remote.workspaceID, remote: remote)
        for view in await coordinator.list() {
            let title = await local.titles[view.localSurfaceID ?? ""]
            #expect(title == (view.surfaceID == remote.first ? "Claude" : "Codex"))
        }
    }
    @Test func fullyDetachedMirrorCanBeRecreatedWhileItsOldWorkspaceStillExists() async throws {
        let local = MirrorTestLocal(), remote = MirrorTestRemote()
        let coordinator = WorkspaceMirrorCoordinator(local: local, executable: URL(fileURLWithPath: "/tmp/viewer"), stateDirectory: URL(fileURLWithPath: "/tmp/state"))
        let host = HostIdentity(id: "host", publicKey: "", certificateSHA256: "", name: "Remote")
        _ = try await coordinator.create(host: host, workspaceID: remote.workspaceID, remote: remote)
        for view in await coordinator.list() { try await coordinator.detach(view.id) }
        let restored = try await coordinator.create(host: host, workspaceID: remote.workspaceID, remote: remote)
        #expect(restored["existing"].bool != true)
        #expect(await coordinator.list().count == 2)
        #expect(await local.commands.count == 4)
    }
    @Test func reopeningExistingMirrorSelectsItWithoutStartingMoreViewers() async throws {
        let local = MirrorTestLocal(), remote = MirrorTestRemote()
        let coordinator = WorkspaceMirrorCoordinator(local: local, executable: URL(fileURLWithPath: "/tmp/viewer"), stateDirectory: URL(fileURLWithPath: "/tmp/state"))
        let host = HostIdentity(id: "host", publicKey: "", certificateSHA256: "", name: "Remote")
        _ = try await coordinator.create(host: host, workspaceID: remote.workspaceID, remote: remote)
        let existing = try await coordinator.create(host: host, workspaceID: remote.workspaceID, remote: remote)
        #expect(existing["existing"].bool == true)
        #expect(await local.commands.count == 2)
        #expect(await local.methods.filter { $0 == "workspace.select" }.count == 2)
    }
    @Test func signedTLSClientReceivesReplayAndSendsToSameProducer() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = BridgeState(directory: directory); try state.initialize(); let authority = try state.authority(name: "Mirror host")
        let cmux = MirrorTestCmux(); let service = SessionService(cmux: cmux, home: directory, transcriptRoots: [])
        let ready = AsyncThrowingStream<Int, any Error>.makeStream()
        let server = Task {
            do { try await HTTPServer().run(host: "127.0.0.1", port: 0, certificate: state.certificate, key: state.key,
                router: BridgeRouter(service: service, authority: authority, mirrors: RemoteMirrorService(cmux: cmux)),
                onListening: { ready.continuation.yield($0); ready.continuation.finish() }) }
            catch { ready.continuation.finish(throwing: error); throw error }
        }
        defer { server.cancel() }
        var iterator = ready.stream.makeAsyncIterator(); let port = try #require(await iterator.next())
        let bootstrap = try await authority.open(endpoint: .init(host: "127.0.0.1", port: port), workspaces: [cmux.workspaceID])
        let enrollment = try EnrollmentClient(bootstrap: bootstrap, privateKey: IdentityCryptography().generatePrivateKey(), name: "Local Mac", kind: "mac", capabilities: [.workspaceRead, .terminalRead, .terminalInput])
        defer { enrollment.close() }
        _ = try await authority.submit(enrollment.request)
        try await authority.approve(requestID: enrollment.request.value.requestID,
            scope: .init(workspaces: [cmux.workspaceID], capabilities: [.workspaceRead, .terminalRead, .terminalInput]))
        let connection = try enrollment.connection(from: await authority.status(enrollment.request).value)
        let remote = try RemoteMirrorClient(connection: connection)
        let snapshot = try await remote.replay(workspaceID: cmux.workspaceID, surfaceID: cmux.surfaceID)
        #expect(snapshot.allowsInput); #expect(snapshot.runtimeEpoch == "producer-1")
        let receipt = try await remote.input(workspaceID: cmux.workspaceID, surfaceID: cmux.surfaceID, request: .init(runtimeEpoch: snapshot.runtimeEpoch, text: "hello\r"))
        #expect(receipt.accepted); #expect(await cmux.inputs == 1)
        await cmux.setEpoch("producer-2")
        do { _ = try await remote.input(workspaceID: cmux.workspaceID, surfaceID: cmux.surfaceID, request: .init(runtimeEpoch: snapshot.runtimeEpoch, text: "stale")); Issue.record("Expected stale producer denial") }
        catch { #expect((error as? BridgeError)?.code == "stale_binding") }
        #expect(await cmux.inputs == 1)
        server.cancel(); try await server.value
    }
    @Test func viewingNeverWakesAHibernatedAgent() async throws {
        let cmux = MirrorTestCmux(); await cmux.hibernate(); let service = RemoteMirrorService(cmux: cmux)
        await #expect(throws: BridgeError.self) { try await service.replay(workspaceID: cmux.workspaceID, surfaceID: cmux.surfaceID) }
        #expect(await cmux.replays == 0)
    }
    @Test func characterReplayPreservesUnicodeAndRejectsControlInjection() async throws {
        let cmux = MirrorTestCmux(); let service = RemoteMirrorService(cmux: cmux)
        let first = try await service.replay(workspaceID: cmux.workspaceID, surfaceID: cmux.surfaceID)
        #expect(String(decoding: first.bytes, as: UTF8.self).contains("👩‍💻"))
        await cmux.setText("\u{1B}]52;c;bad\u{7}")
        await #expect(throws: BridgeError.self) { try await service.replay(workspaceID: cmux.workspaceID, surfaceID: cmux.surfaceID) }
    }
    @Test func staleRuntimeCannotReceiveInputAndDuplicatesTypeOnce() async throws {
        let cmux = MirrorTestCmux(); let service = RemoteMirrorService(cmux: cmux)
        let operation = MirrorInputRequest(runtimeEpoch: "producer-1", text: "hello\r")
        _ = try await service.input(workspaceID: cmux.workspaceID, surfaceID: cmux.surfaceID, clientID: "client", request: operation) {}
        _ = try await service.input(workspaceID: cmux.workspaceID, surfaceID: cmux.surfaceID, clientID: "client", request: operation) {}
        #expect(await cmux.inputs == 1)
        await cmux.setEpoch("producer-2")
        await #expect(throws: BridgeError.self) {
            try await service.input(workspaceID: cmux.workspaceID, surfaceID: cmux.surfaceID, clientID: "client", request: .init(runtimeEpoch: "producer-1", text: "wrong")) {}
        }
        #expect(await cmux.inputs == 1)
    }
    @Test func unknownInputOutcomeIsNotRetried() async throws {
        let cmux = MirrorTestCmux(); await cmux.setFailure(); let service = RemoteMirrorService(cmux: cmux)
        let operation = MirrorInputRequest(runtimeEpoch: "producer-1", text: "once")
        for _ in 0..<2 {
            do { _ = try await service.input(workspaceID: cmux.workspaceID, surfaceID: cmux.surfaceID, clientID: "client", request: operation) {}; Issue.record("Expected outcome unknown") }
            catch { #expect((error as? BridgeError)?.code == "outcome_unknown") }
        }
        #expect(await cmux.inputs == 1)
    }
    @Test func projectionDetachPreservesOtherViewAndRebindFailsClosed() async throws {
        let local = MirrorTestLocal(); let remote = MirrorTestRemote()
        let coordinator = WorkspaceMirrorCoordinator(local: local, executable: URL(fileURLWithPath: "/tmp/a path/viewer"), stateDirectory: URL(fileURLWithPath: "/tmp/private state"))
        let host = HostIdentity(id: "host", publicKey: "", certificateSHA256: "", name: "Remote")
        _ = try await coordinator.create(host: host, workspaceID: remote.workspaceID, remote: remote)
        let projections = await coordinator.list(); #expect(projections.count == 2)
        let methods = await local.methods
        #expect(!methods.contains("surface.respawn")); #expect(!methods.contains("workspace.close"))
        #expect(await local.commands.allSatisfy { $0.hasPrefix("'/tmp/a path/viewer' mirror view") && !$0.contains("privateKey") })
        try await coordinator.detach(projections[0].id)
        await #expect(throws: BridgeError.self) { try await coordinator.replay(projections[0].id) }
        _ = try await coordinator.replay(projections[1].id)
        await remote.changeEpoch()
        await #expect(throws: BridgeError.self) { try await coordinator.replay(projections[1].id) }
        #expect(await remote.inputs == 0)
    }
    @Test func terminalScopeIsRequiredBeforeCmuxIsRead() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = BridgeState(directory: directory); try state.initialize(); let authority = try state.authority(name: "Fixture")
        let cmux = MirrorTestCmux(); let workspace = cmux.workspaceID
        let bootstrap = try await authority.open(endpoint: .init(host: "127.0.0.1", port: 7740), workspaces: [workspace])
        let enrollment = try EnrollmentClient(bootstrap: bootstrap, privateKey: IdentityCryptography().generatePrivateKey(), name: "Mac", kind: "mac")
        defer { enrollment.close() }
        _ = try await authority.submit(enrollment.request)
        try await authority.approve(requestID: enrollment.request.value.requestID, scope: .init(workspaces: [workspace], capabilities: [.workspaceRead]))
        let connection = try enrollment.connection(from: await authority.status(enrollment.request).value)
        let uri = "/v2/workspaces/\(workspace)/terminals/\(cmux.surfaceID)/replay"
        let announcement = try await authority.announcement()
        let proof = RequestProof(epoch: announcement.value.epoch, hostID: connection.host.id, clientID: connection.grant.value.clientID, method: "GET", uri: uri,
                                 bodySHA256: IdentityCryptography().digest(Data()), nonce: UUID().uuidString, timestamp: Int(Date().timeIntervalSince1970))
        let signed = try IdentityCryptography().sign(proof, domain: "request", privateKey: connection.privateKey)
        let service = SessionService(cmux: cmux, home: directory, transcriptRoots: [])
        let router = BridgeRouter(service: service, authority: authority, mirrors: RemoteMirrorService(cmux: cmux))
        let response = await router.respond(method: "GET", uri: uri, authorization: "CmuxV2 " + (try JSONEncoder().encode(signed)).base64EncodedString(), body: Data())
        #expect(response.0 == 403); #expect(await cmux.calls == 0)
    }
    @Test func navigationRejectsSecretAndCommandParameters() throws {
        let id = String(repeating: "a", count: 64)
        #expect(try MacNavigationRequest(url: MacNavigationRequest.url(hostID: id)).hostID == id)
        #expect(throws: BridgeError.self) { try MacNavigationRequest(url: URL(string: "cmux-remote-mac://devices?host=\(id)&command=rm")!) }
        #expect(throws: BridgeError.self) { try MacNavigationRequest(url: URL(string: "cmux-remote-mac://devices?token=secret")!) }
    }
    @Test func terminalInputReceiptsSurviveRestartAndRequireFreshAuthority() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cmux = MirrorTestCmux(), request = MirrorInputRequest(runtimeEpoch: "producer-1", text: "private-terminal-input")
        let first = RemoteMirrorService(cmux: cmux, mutations: MutationLedger(directory: directory))
        _ = try await first.input(workspaceID: cmux.workspaceID, surfaceID: cmux.surfaceID, clientID: "client", request: request) {}
        let restarted = RemoteMirrorService(cmux: cmux, mutations: MutationLedger(directory: directory))
        _ = try await restarted.input(workspaceID: cmux.workspaceID, surfaceID: cmux.surfaceID, clientID: "client", request: request) {}
        #expect(await cmux.inputs == 1)
        await #expect(throws: BridgeError.self) {
            _ = try await restarted.input(workspaceID: cmux.workspaceID, surfaceID: cmux.surfaceID, clientID: "client", request: request) {
                throw BridgeError("scope_denied", "Revoked", status: 403)
            }
        }
        #expect(await cmux.inputs == 1)
        let raw = try String(contentsOf: directory.appendingPathComponent("mutation-receipts.ndjson"), encoding: .utf8)
        #expect(!raw.contains("private-terminal-input"))
    }
    @Test func unknownTerminalInputRemainsUnknownAfterRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cmux = MirrorTestCmux(); await cmux.setFailure()
        let request = MirrorInputRequest(runtimeEpoch: "producer-1", text: "once")
        for _ in 0..<2 {
            let restarted = RemoteMirrorService(cmux: cmux, mutations: MutationLedger(directory: directory))
            do { _ = try await restarted.input(workspaceID: cmux.workspaceID, surfaceID: cmux.surfaceID, clientID: "client", request: request) {}; Issue.record("Expected unknown") }
            catch { #expect((error as? BridgeError)?.code == "outcome_unknown") }
        }
        #expect(await cmux.inputs == 1)
    }

}

import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteClient
import CmuxRemoteMac

@Suite struct ManagedSharingTests {
    @Test @MainActor func ownerApprovalAndConnectionsSurviveSharingRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = BridgeState(directory: root); try state.initialize()
        let authority = try state.authority(name: "Fixture")
        let service = SessionService(cmux: DemoCmux(transcript: root.appendingPathComponent("new.jsonl").path, project: root.path), home: root, transcriptRoots: [root])
        let sharing = ManagedSharingService(state: state, authority: authority, router: BridgeRouter(service: service, authority: authority), listen: "127.0.0.1", port: 0, advertise: false)
        let ready = AsyncStream<Void>.makeStream()
        let server = Task { try await OwnerControlServer().run(path: root.appendingPathComponent("owner.sock").path, authority: authority, service: service, sharing: sharing, onListening: { ready.continuation.yield(()); ready.continuation.finish() }) }
        defer { server.cancel() }
        var iterator = ready.stream.makeAsyncIterator(); _ = await iterator.next()
        let started = try await sharing.start(); let port = try #require(started["port"].int)
        let bootstrap = try await authority.open(endpoint: BridgeEndpoint(host: "127.0.0.1", port: port), workspaces: ["11111111-1111-1111-1111-111111111111"])
        let enrollment = try EnrollmentClient(bootstrap: bootstrap, privateKey: IdentityCryptography().generatePrivateKey(), name: "Fixture phone", kind: "iphone", capabilities: [.workspaceRead, .conversationRead])
        defer { enrollment.close() }
        _ = try await enrollment.submit()
        let model = MacSharingModel(owner: UnixSocketClient(path: root.appendingPathComponent("owner.sock").path))
        await model.refresh(); #expect(model.pending.count == 1 && model.isSharing)
        let request = try #require(model.pending.first); await model.approve(request)
        #expect(model.pending.isEmpty && model.clients.count == 1)
        let client = try RemoteClient(connection: enrollment.connection(from: try await enrollment.status()))
        defer { client.close() }
        let before = try await client.get("/v1/workspaces", as: JSONValue.self)
        #expect(before["workspaces"].array?.count == 1)
        await model.setSharing(false)
        #expect(!model.isSharing && model.errorCode == nil)
        // The same owner socket remains usable while no HTTPS listener is running.
        let local = try await UnixSocketClient(path: root.appendingPathComponent("owner.sock").path).request("bridge.workspaces", params: [:])
        #expect(local["workspaces"].array?.count == 1)
        #expect(try await authority.enrolledClients().first?.scope == request.scope)
        await model.setSharing(true); #expect(model.isSharing && model.errorCode == nil)
        let after = try await client.get("/v1/workspaces", as: JSONValue.self)
        #expect(after == before)
        await model.revoke(clientID: request.clientID)
        #expect(model.clients.isEmpty)
        await #expect(throws: BridgeError.self) { _ = try await client.get("/v1/workspaces", as: JSONValue.self) }
        _ = await sharing.stop(); server.cancel(); try await server.value
    }

    @Test func bindFailureDoesNotReportSharingSuccess() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = BridgeState(directory: root); try state.initialize()
        let authority = try state.authority(name: "Fixture")
        let service = SessionService(cmux: DemoCmux(transcript: root.appendingPathComponent("new.jsonl").path, project: root.path), home: root, transcriptRoots: [root])
        let router = BridgeRouter(service: service, authority: authority)
        let first = ManagedSharingService(state: state, authority: authority, router: router, listen: "127.0.0.1", port: 0, advertise: false)
        let started = try await first.start(); let port = try #require(started["port"].int)
        let second = ManagedSharingService(state: state, authority: authority, router: router, listen: "127.0.0.1", port: port, advertise: false)
        do { _ = try await second.start(); Issue.record("Occupied port must fail") }
        catch { #expect((error as? BridgeError)?.code == "sharing_start_failed") }
        let status = await second.status(); #expect(status["state"].string == "stopped")
        #expect(status["error_code"].string == "sharing_start_failed")
        _ = await first.stop()
    }
}

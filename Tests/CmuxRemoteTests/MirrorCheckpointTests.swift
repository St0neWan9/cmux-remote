import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteMac

@Suite struct MirrorCheckpointTests {
    let workspace = "11111111-1111-1111-1111-111111111111"
    let surface = "22222222-2222-2222-2222-222222222222"
    func host() throws -> HostIdentity {
        let crypto = IdentityCryptography(), key = try crypto.publicKey(privateKey: crypto.generatePrivateKey())
        return .init(id: try crypto.identityID(publicKey: key), publicKey: key, certificateSHA256: String(repeating: "a", count: 64), name: "Remote")
    }
    func coordinator(_ local: ReconciliationLocalFixture, directory: URL) -> WorkspaceMirrorCoordinator {
        .init(local: local, executable: URL(fileURLWithPath: "/tmp/viewer"), stateDirectory: directory,
              topologyTicks: { AsyncStream { $0.finish() } }, checkpoints: MirrorCheckpointRepository(directory: directory))
    }
    @Test func restartRetainsExactViewIDsWithoutAnyLocalMutation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try host(), local = ReconciliationLocalFixture()
        let remote = ReconciliationRemoteFixture(.init(id: workspace, title: "Agents", layout: .null, surfaces: [.init(id: surface, paneID: surface, title: "Claude")]))
        let before = coordinator(local, directory: directory)
        _ = try await before.create(host: host, workspaceID: workspace, remote: remote)
        let views = await before.list(), commands = await local.commands, selections = await local.selections
        let after = coordinator(local, directory: directory)
        #expect(try await after.restore { _, _ in (host, remote) } == 1)
        #expect(await after.list().map(\.id) == views.map(\.id))
        #expect(await local.commands == commands); #expect(await local.selections == selections)
        let replay = try await after.replay(views[0].id)
        #expect(replay.runtimeEpoch == views[0].runtimeEpoch)
        let attrs = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("mirror-checkpoints.json").path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        try await after.detach(views[0].id)
        #expect(try await MirrorCheckpointRepository(directory: directory).load().isEmpty)
    }
    @Test func replacedProducerAndRevokedAuthorityFailClosed() async throws {
        for revoked in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let host = try host(), local = ReconciliationLocalFixture()
            let remote = ReconciliationRemoteFixture(.init(id: workspace, title: "Agents", layout: .null, surfaces: [.init(id: surface, paneID: surface, title: "Claude")]))
            _ = try await coordinator(local, directory: directory).create(host: host, workspaceID: workspace, remote: remote)
            if !revoked { await remote.replaceRuntime() }
            let after = coordinator(local, directory: directory), commands = await local.commands
            let count = try await after.restore { _, _ in
                if revoked { throw BridgeError("scope_denied", "Revoked", status: 403) }
                return (host, remote)
            }
            #expect(count == 0); #expect(await after.list().isEmpty); #expect(await local.commands == commands)
            let status = try #require(await after.syncStatus().first)
            #expect(status.state == "paused")
            #expect(status.errorCode == (revoked ? "scope_denied" : "stale_binding"))
        }
    }

    @Test func failedRestoreReportsItsReadFailureAndCanBeRevalidatedWithoutWrites() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try host(), local = ReconciliationLocalFixture()
        let remote = ReconciliationRemoteFixture(.init(id: workspace, title: "Agents", layout: .null,
            surfaces: [.init(id: surface, paneID: surface, title: "Claude")]))
        let before = coordinator(local, directory: directory)
        _ = try await before.create(host: host, workspaceID: workspace, remote: remote)
        let views = await before.list(), commands = await local.commands
        let restored = coordinator(local, directory: directory)
        #expect(try await restored.restore { _, _ in throw BridgeError("socket_unavailable", "Offline") } == 0)
        let failed = try #require(await restored.syncStatus().first)
        #expect(failed.errorCode == "socket_unavailable")
        #expect(failed.localWorkspaceID == views[0].localWorkspaceID)
        #expect(try await MirrorCheckpointRepository(directory: directory).load().count == 1)
        #expect(try await restored.restore { _, _ in (host, remote) } == 1)
        #expect(await restored.syncStatus().count == 1)
        #expect(await restored.syncStatus().first?.state == "watching")
        #expect(await restored.list().map(\.id) == views.map(\.id))
        #expect(await local.commands == commands)
    }
    @Test func persistingHealthyMirrorKeepsAnotherOfflineCheckpoint() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try host(), local = ReconciliationLocalFixture()
        let remote = ReconciliationRemoteFixture(.init(id: workspace, title: "Agents", layout: .null,
            surfaces: [.init(id: surface, paneID: surface, title: "Claude")]))
        let before = coordinator(local, directory: directory)
        _ = try await before.create(host: host, workspaceID: workspace, remote: remote)
        let repository = MirrorCheckpointRepository(directory: directory)
        let healthy = try #require(try await repository.load().first)
        let offlineWorkspace = UUID().uuidString.lowercased(), offlineSurface = UUID().uuidString.lowercased(), localWorkspace = UUID().uuidString
        var projection = MirrorProjection(hostID: host.id, workspaceID: offlineWorkspace,
            surfaceID: offlineSurface, runtimeEpoch: "offline-producer")
        projection.localWorkspaceID = localWorkspace; projection.localSurfaceID = UUID().uuidString
        let offline = MirrorCheckpoint(host: host, localWorkspaceID: localWorkspace,
            snapshot: .init(id: offlineWorkspace, title: "Offline", layout: .null,
                surfaces: [.init(id: offlineSurface, paneID: offlineSurface, title: "Codex")]), projections: [projection])
        try await repository.save([healthy, offline])
        let restored = coordinator(local, directory: directory)
        #expect(try await restored.restore { _, id in
            if id == offlineWorkspace { throw BridgeError("mirror_remote_unavailable", "Offline") }
            return (host, remote)
        } == 1)
        let view = try #require(await restored.list().first)
        try await restored.detach(view.id)
        let saved = try await repository.load()
        #expect(saved.count == 1)
        #expect(saved.first?.snapshot.id == offlineWorkspace)
        #expect(saved.first?.projections.first?.id == projection.id)
        try await restored.detach(hostID: host.id)
        #expect(try await repository.load().isEmpty, "Explicit forget removes offline records too")
    }
    @Test func changedLocalMembershipCannotRestore() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try host(), local = ReconciliationLocalFixture()
        let remote = ReconciliationRemoteFixture(.init(id: workspace, title: "Agents", layout: .null, surfaces: [.init(id: surface, paneID: surface, title: "Claude")]))
        let mirror = coordinator(local, directory: directory)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        // A foreign local tab makes reconciliation fail before layout mutation.
        _ = await local.addForeignTerminal()
        await #expect(throws: BridgeError.self) { _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace, force: true) }
        let restored = coordinator(local, directory: directory)
        #expect(try await restored.restore { _, _ in (host, remote) } == 0)
        #expect(await restored.list().isEmpty)
    }
    @Test func unknownLayoutWriteInvalidatesCheckpointBeforeMutation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try host(), local = ReconciliationLocalFixture(), second = "33333333-3333-3333-3333-333333333333"
        let remote = ReconciliationRemoteFixture(.init(id: workspace, title: "Agents", layout: .null,
            surfaces: [.init(id: surface, paneID: surface, title: "Claude"), .init(id: second, paneID: second, title: "Codex")]))
        let mirror = coordinator(local, directory: directory)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        await local.loseNextMove()
        await #expect(throws: BridgeError.self) { _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace, force: true) }
        #expect(try await MirrorCheckpointRepository(directory: directory).load().isEmpty)
    }

    @Test func localAgentRepurposingPreventsRestoration() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let host = try host(), local = ReconciliationLocalFixture()
        let remote = ReconciliationRemoteFixture(.init(id: workspace, title: "Agents", layout: .null,
            surfaces: [.init(id: surface, paneID: surface, title: "Claude")]))
        let before = coordinator(local, directory: directory)
        _ = try await before.create(host: host, workspaceID: workspace, remote: remote)
        let view = try #require(await before.list().first), id = try #require(view.localSurfaceID)
        await local.repurpose(id)
        let after = coordinator(local, directory: directory)
        #expect(try await after.restore { _, _ in (host, remote) } == 0)
        #expect(await after.list().isEmpty)
    }

}

import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteMac

@Suite struct MirrorReconciliationTests {
    @Test func temporaryRemoteReadFailureKeepsBindingsAndCanRecoverWithoutLocalWrites() async throws {
        let local = ReconciliationLocalFixture(), remote = ReconciliationRemoteFixture(snapshot([first, second]))
        let mirror = coordinator(local)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        let before = await mirror.list(), commands = await local.commands
        await remote.failReads("mirror_remote_unavailable")
        await #expect(throws: BridgeError.self) { _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace) }
        #expect(await mirror.syncStatus().first?.state == "reconnecting")
        #expect(await mirror.list().map(\.id) == before.map(\.id))
        await remote.failReads(nil)
        _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace)
        #expect(await mirror.syncStatus().first?.state == "watching")
        #expect(await local.commands == commands)
        #expect(await local.closed.isEmpty)
    }
    @Test func unchangedSourceDoesNotHideForeignLocalMembership() async throws {
        let local = ReconciliationLocalFixture(), remote = ReconciliationRemoteFixture(snapshot([first, second]))
        let mirror = coordinator(local)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        _ = await local.addForeignTerminal()
        await #expect(throws: BridgeError.self) { _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace) }
        #expect(await mirror.syncStatus().first?.state == "paused")
        #expect(await local.commands.count == 2)
        #expect(await local.closed.isEmpty)
    }
    let workspace = "11111111-1111-1111-1111-111111111111"
    let first = "22222222-2222-2222-2222-222222222222"
    let second = "33333333-3333-3333-3333-333333333333"
    let third = "55555555-5555-5555-5555-555555555555"
    let host = HostIdentity(id: "host", publicKey: "", certificateSHA256: "", name: "Remote")
    func snapshot(_ ids: [String], grouped: Bool = false) -> MirrorWorkspaceSnapshot {
        .init(id: workspace, title: "Agents", layout: .null,
              surfaces: ids.map { .init(id: $0, paneID: grouped ? first : $0, title: $0 == first ? "Claude" : $0 == third ? "New terminal" : "Codex") })
    }
    func coordinator(_ local: ReconciliationLocalFixture) -> WorkspaceMirrorCoordinator {
        .init(local: local, executable: URL(fileURLWithPath: "/tmp/viewer"), stateDirectory: URL(fileURLWithPath: "/tmp/state"), topologyTicks: { AsyncStream { $0.finish() } })
    }
    @Test func initialThreeTabsPreserveOrderWhenCmuxInsertsAfterSelected() async throws {
        let local = ReconciliationLocalFixture(), remote = ReconciliationRemoteFixture(snapshot([first, second, third], grouped: true))
        let mirror = coordinator(local)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        let views = await mirror.list()
        let expected = [first, second, third].map { id in views.first { $0.surfaceID == id }!.localSurfaceID! }
        #expect(await local.panes.values.first == expected)
    }
    @Test func explicitSyncCanRestoreOwnedTabOrderWithoutSourceChanges() async throws {
        let local = ReconciliationLocalFixture(), remote = ReconciliationRemoteFixture(snapshot([first, second, third], grouped: true))
        let mirror = coordinator(local)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        let views = await mirror.list()
        let order = [first, second, third].map { id in views.first { $0.surfaceID == id }!.localSurfaceID! }
        _ = try await local.request("surface.reorder", params: ["workspace_id": .string(local.workspaceID), "surface_id": .string(order[2]), "index": .number(0), "focus": .bool(false)])
        _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace, force: true)
        #expect(await local.panes.values.first == order)
        #expect(await local.commands.count == 3)
    }
    @Test func newlyCreatedNativeTabWaitsForReadPublicationWithoutDuplicateCreation() async throws {
        let local = ReconciliationLocalFixture(), remote = ReconciliationRemoteFixture(snapshot([first, second]))
        let mirror = coordinator(local)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        let original = await mirror.list()
        await local.delayNextCreation(reads: 3)
        await remote.change(snapshot([first, second, third]))
        _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace)
        #expect(await local.commands.count == 3)
        #expect(await mirror.list().count == 3)
        #expect(await mirror.syncStatus().first?.state == "watching")
        for view in original { #expect(await mirror.list().contains { $0.id == view.id && $0.localSurfaceID == view.localSurfaceID }) }
    }
    @Test(.timeLimit(.minutes(1))) func injectedTicksDriveAutomaticSyncAndStopOnForget() async throws {
        let local = ReconciliationLocalFixture(), remote = ReconciliationRemoteFixture(snapshot([first, second]))
        let ticks = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let terminated = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        ticks.continuation.onTermination = { _ in terminated.continuation.yield(()); terminated.continuation.finish() }
        let mirror = WorkspaceMirrorCoordinator(local: local, executable: URL(fileURLWithPath: "/tmp/viewer"), stateDirectory: URL(fileURLWithPath: "/tmp/state"), topologyTicks: { ticks.stream })
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        await remote.change(snapshot([second, first, third], grouped: true)); ticks.continuation.yield(())
        var events = local.renames.stream.makeAsyncIterator()
        while let title = await events.next() { if title == "New terminal" { break } }
        #expect(await mirror.list().count == 3)
        #expect(await local.panes.count == 1); #expect(await local.selections == 1)
        try await mirror.detach(hostID: host.id)
        var stopped = terminated.stream.makeAsyncIterator(); _ = await stopped.next()
        #expect(await mirror.syncStatus().isEmpty)
    }
    @Test func nestedSplitChangesUseExistingViews() async throws {
        let local = ReconciliationLocalFixture(), remote = ReconciliationRemoteFixture(snapshot([first, second]))
        let mirror = coordinator(local)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        let initial = await mirror.list()
        let values = snapshot([first, second, third])
        let leaf: (String) -> JSONValue = { .object(["pane": .object(["id": .string($0)])]) }
        let nested: JSONValue = .object(["direction": .string("vertical"), "children": .array([leaf(first),
            .object(["direction": .string("horizontal"), "children": .array([leaf(second), leaf(third)])])])])
        await remote.change(.init(id: workspace, title: "Agents", layout: nested, surfaces: values.surfaces))
        _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace)
        #expect(await local.directions == ["down", "right"])
        #expect(await local.commands.count == 3)
        let current = await mirror.list()
        for view in initial { #expect(current.contains { $0.id == view.id && $0.localSurfaceID == view.localSurfaceID }) }
    }
    @Test func localForeignTerminalPausesBeforeAnyMutation() async throws {
        let local = ReconciliationLocalFixture(), remote = ReconciliationRemoteFixture(snapshot([first, second]))
        let mirror = coordinator(local)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        _ = await local.addForeignTerminal(); await remote.change(snapshot([first, second, third]))
        await #expect(throws: BridgeError.self) { _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace) }
        #expect(await local.commands.count == 2); #expect(await local.closed.isEmpty)
        #expect(await mirror.syncStatus().first?.errorCode == "mirror_local_changed")
    }
    @Test func lostMoveReceiptPausesWithoutRepeatingTheMove() async throws {
        let local = ReconciliationLocalFixture(), remote = ReconciliationRemoteFixture(snapshot([first, second]))
        let mirror = coordinator(local)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        await remote.change(snapshot([first, second], grouped: true)); await local.loseNextMove()
        for _ in 0..<2 {
            await #expect(throws: BridgeError.self) { _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace) }
        }
        #expect(await local.methods.filter { $0 == "surface.move" }.count == 1)
        #expect(await mirror.syncStatus().first?.errorCode == "outcome_unknown")
    }
    @Test func replacedProducerCannotBeReattachedByTopologyRefresh() async throws {
        let local = ReconciliationLocalFixture(), remote = ReconciliationRemoteFixture(snapshot([first, second]))
        let mirror = coordinator(local)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        await remote.replaceRuntime(); await remote.change(snapshot([first, second, third]))
        await #expect(throws: BridgeError.self) { _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace) }
        #expect(await local.commands.count == 2); #expect(await local.closed.isEmpty)
        #expect(await mirror.syncStatus().first?.errorCode == "stale_binding")
    }
    @Test func retiredRemovedProducerCanBeClosedButRepurposedLocalAgentCannot() async throws {
        for repurpose in [false, true] {
            let local = ReconciliationLocalFixture(), remote = ReconciliationRemoteFixture(snapshot([first, second]))
            let mirror = coordinator(local)
            _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
            let removed = try #require(await mirror.list().first { $0.surfaceID == first })
            try await mirror.detach(removed.id, reason: "stale_binding")
            if repurpose { await local.repurpose(removed.localSurfaceID!) }
            await remote.change(snapshot([second]))
            if repurpose {
                await #expect(throws: BridgeError.self) { _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace) }
                #expect(await local.closed.isEmpty)
            } else {
                _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace)
                #expect(await local.closed == [removed.localSurfaceID!]); #expect(await local.commands.count == 2)
            }
        }
    }
    @Test func titleOnlyChangeDoesNotMoveOrRestartViews() async throws {
        let local = ReconciliationLocalFixture(), initial = snapshot([first, second])
        let remote = ReconciliationRemoteFixture(initial), mirror = coordinator(local)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        await remote.change(.init(id: workspace, title: "Agents", layout: initial.layout,
            surfaces: initial.surfaces.map { .init(id: $0.id, paneID: $0.paneID, title: "Renamed " + $0.title) }))
        _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace)
        #expect(await local.commands.count == 2)
        #expect(await !local.methods.contains("surface.move")); #expect(await !local.methods.contains("surface.reorder"))
        #expect(await local.titles.values.allSatisfy { $0.hasPrefix("Renamed ") })
    }
    @Test func locallyExitedRemovedViewerDoesNotPauseRemainingWorkspace() async throws {
        let local = ReconciliationLocalFixture(), remote = ReconciliationRemoteFixture(snapshot([first, second]))
        let mirror = coordinator(local)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        let removed = try #require(await mirror.list().first { $0.surfaceID == first })
        try await mirror.detach(removed.id, reason: "not_found")
        await local.remove(removed.localSurfaceID!)
        await remote.change(snapshot([second]))
        _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace)
        #expect(await mirror.list().count == 1)
        #expect(await local.closed.isEmpty)
        #expect(await mirror.syncStatus().first?.state == "watching")
    }
    @Test(.timeLimit(.minutes(1))) func lateReplayCannotResurrectDeliberatelyRemovedView() async throws {
        let local = ReconciliationLocalFixture(), remote = ReconciliationRemoteFixture(snapshot([first, second]))
        let mirror = coordinator(local)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        let removed = try #require(await mirror.list().first { $0.surfaceID == first })
        await remote.holdNextReplay()
        let reading = Task { try await mirror.replay(removed.id) }
        var started = remote.replayStarted.stream.makeAsyncIterator(); _ = await started.next()
        await remote.change(snapshot([second]))
        _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace)
        await remote.releaseReplay()
        await #expect(throws: BridgeError.self) { _ = try await reading.value }
        #expect(await mirror.syncStatus().first?.state == "watching")
        _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace, force: true)
        #expect(await mirror.list().count == 1)
    }
    @Test func sourceAddRemoveAndTabOrderPreserveExistingViewersAndWorkspace() async throws {
        let local = ReconciliationLocalFixture(), remote = ReconciliationRemoteFixture(snapshot([first, second]))
        let mirror = coordinator(local)
        _ = try await mirror.create(host: host, workspaceID: workspace, remote: remote)
        let original = await mirror.list()
        await remote.change(snapshot([second, first, third], grouped: true))
        _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace)
        let added = await mirror.list()
        #expect(added.count == 3)
        for view in original { #expect(added.contains { $0.id == view.id && $0.localSurfaceID == view.localSurfaceID }) }
        #expect(await local.commands.count == 3)
        #expect(await local.panes.count == 1)
        #expect(await local.selections == 1)
        let ordered = [second, first, third].compactMap { id in added.first { $0.surfaceID == id }?.localSurfaceID }
        #expect(await local.panes.values.first == ordered)
        await remote.change(snapshot([third, second]))
        _ = try await mirror.reconcile(hostID: host.id, workspaceID: workspace)
        #expect(await mirror.list().count == 2)
        let firstLocal = try #require(original.first { $0.surfaceID == first }?.localSurfaceID)
        #expect(await local.closed == [firstLocal])
        #expect(await local.commands.count == 3)
        #expect(await local.panes.count == 2)
        #expect(await local.selections == 1)
    }
}

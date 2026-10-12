import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteMac

@Suite struct NativeWorkspaceCatalogTests {
    let remoteWorkspace = "11111111-1111-1111-1111-111111111111"
    let first = "22222222-2222-2222-2222-222222222222"
    let second = "33333333-3333-3333-3333-333333333333"
    func host() throws -> HostIdentity {
        let crypto = IdentityCryptography(), key = try crypto.publicKey(privateKey: crypto.generatePrivateKey())
        return .init(id: try crypto.identityID(publicKey: key), publicKey: key, certificateSHA256: String(repeating: "a", count: 64), name: "Remote")
    }
    func catalog(_ directory: URL, local: CatalogLocalFixture, group: CatalogGroupFixture, host: HostIdentity) -> (NativeWorkspaceCatalog, WorkspaceMirrorCoordinator) {
        let mirrors = WorkspaceMirrorCoordinator(local: local, executable: URL(fileURLWithPath: "/tmp/viewer"), stateDirectory: directory,
            topologyTicks: { AsyncStream { $0.finish() } })
        let remote = ReconciliationRemoteFixture(.init(id: remoteWorkspace, title: "Agents", layout: .null,
            surfaces: [.init(id: first, paneID: first, title: "Claude"), .init(id: second, paneID: second, title: "Codex")]))
        let catalog = NativeWorkspaceCatalog(local: local, repository: NativeWorkspaceRepository(directory: directory), mirrors: mirrors,
            grouping: group, executable: URL(fileURLWithPath: "/tmp/viewer"), stateDirectory: directory, waitTimeout: .milliseconds(20)) { id, workspace in
                #expect(id == host.id); #expect(workspace == remoteWorkspace)
                return (host, remote)
            }
        return (catalog, mirrors)
    }
    @Test func inventoryCreatesPendingRowsAndSelectionAttachesIntoTheSameWorkspace() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = CatalogLocalFixture(), group = CatalogGroupFixture(), host = try host()
        let (catalog, mirrors) = catalog(directory, local: local, group: group, host: host)
        try await catalog.sync(host: host, workspaces: [.init(id: remoteWorkspace, title: "Agents")])
        let row = try #require(try await catalog.rows().first), seed = try #require(row.seed)
        #expect(row.state == "pending"); #expect(await mirrors.list().isEmpty)
        #expect(await local.commands.count == 1)
        #expect(await local.commands.first?.contains("mirror pending") == true)
        #expect(await group.workspaces == [seed.workspaceID])
        #expect(try await catalog.wait(row.id) == false)
        await #expect(throws: BridgeError.self) { _ = try await catalog.open(row.id, workspaceID: seed.workspaceID, surfaceID: seed.surfaceID) }
        await local.select(seed.workspaceID); try await catalog.refreshSelection()
        #expect(try await catalog.wait(row.id))
        let projection = try await catalog.open(row.id, workspaceID: seed.workspaceID, surfaceID: seed.surfaceID)
        #expect(await mirrors.list().count == 2)
        #expect(await mirrors.list().allSatisfy { $0.localWorkspaceID == seed.workspaceID })
        #expect(await local.calls.filter { $0 == "workspace.create" }.count == 1)
        #expect(try await catalog.open(row.id, workspaceID: seed.workspaceID, surfaceID: seed.surfaceID) == projection)
    }
    @Test func persistedPendingRowsAndLostCreationIntentsNeverCreateDuplicates() async throws {
        for lose in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let local = CatalogLocalFixture(), group = CatalogGroupFixture(), host = try host()
            let (firstCatalog, _) = catalog(directory, local: local, group: group, host: host)
            if lose { await local.loseNextCreate() }
            do { try await firstCatalog.sync(host: host, workspaces: [.init(id: remoteWorkspace, title: "Agents")]) }
            catch { #expect(lose) }
            let (restored, _) = catalog(directory, local: local, group: group, host: host)
            try await restored.sync(host: host, workspaces: [.init(id: remoteWorkspace, title: "Agents")])
            #expect(await local.calls.filter { $0 == "workspace.create" }.count == 1)
            #expect(try await restored.rows().count == 1)
            let attrs = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("native-workspaces.json").path)
            #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }
    @Test func editedOrForeignLocalBindingsCannotActivateRemoteViews() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = CatalogLocalFixture(), group = CatalogGroupFixture(), host = try host()
        let (catalog, mirrors) = catalog(directory, local: local, group: group, host: host)
        try await catalog.sync(host: host, workspaces: [.init(id: remoteWorkspace, title: "Agents")])
        let row = try #require(try await catalog.rows().first), seed = try #require(row.seed)
        await local.select(seed.workspaceID); await local.addForeignSurface(seed.workspaceID)
        await #expect(throws: BridgeError.self) { _ = try await catalog.open(row.id, workspaceID: seed.workspaceID, surfaceID: seed.surfaceID) }
        #expect(await mirrors.list().isEmpty)
        #expect(try await catalog.rows().first?.state == "paused")
    }
    @Test func revokedAuthorityPausesBeforeAnyRemoteProjection() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = CatalogLocalFixture(), group = CatalogGroupFixture(), host = try host()
        let mirrors = WorkspaceMirrorCoordinator(local: local, executable: URL(fileURLWithPath: "/tmp/viewer"), stateDirectory: directory)
        let catalog = NativeWorkspaceCatalog(local: local, repository: NativeWorkspaceRepository(directory: directory), mirrors: mirrors,
            grouping: group, executable: URL(fileURLWithPath: "/tmp/viewer"), stateDirectory: directory) { _, _ in
                throw BridgeError("scope_denied", "Revoked", status: 403)
            }
        try await catalog.sync(host: host, workspaces: [.init(id: remoteWorkspace, title: "Agents")])
        let row = try #require(try await catalog.rows().first), seed = try #require(row.seed)
        await local.select(seed.workspaceID)
        await #expect(throws: BridgeError.self) { _ = try await catalog.open(row.id, workspaceID: seed.workspaceID, surfaceID: seed.surfaceID) }
        #expect(await mirrors.list().isEmpty)
        #expect(try await catalog.rows().first?.errorCode == "scope_denied")
        #expect(await local.calls.filter { $0 == "surface.create" || $0 == "surface.split" }.isEmpty)
    }
    @Test func confirmedRowSurvivesTemporaryNativeGroupingFailure() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = CatalogLocalFixture(), group = CatalogGroupFixture(), host = try host()
        let (catalog, _) = catalog(directory, local: local, group: group, host: host)
        await group.failNextPlacement()
        try await catalog.sync(host: host, workspaces: [.init(id: remoteWorkspace, title: "Agents")])
        #expect(try await catalog.rows().first?.state == "pending")
        try await catalog.sync(host: host, workspaces: [.init(id: remoteWorkspace, title: "Agents")])
        #expect(try await catalog.rows().first?.errorCode == nil)
        #expect(await local.calls.filter { $0 == "workspace.create" }.count == 1)
    }
    @Test func cancelledSelectionWaitCanBeReplacedWithoutDuplicateRows() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = CatalogLocalFixture(), group = CatalogGroupFixture(), host = try host()
        let (catalog, _) = catalog(directory, local: local, group: group, host: host)
        try await catalog.sync(host: host, workspaces: [.init(id: remoteWorkspace, title: "Agents")])
        let row = try #require(try await catalog.rows().first), seed = try #require(row.seed)
        let waiter = Task { try await catalog.wait(row.id) }
        waiter.cancel(); _ = try? await waiter.value
        await local.select(seed.workspaceID); try await catalog.refreshSelection()
        #expect(try await catalog.wait(row.id))
        #expect(await local.calls.filter { $0 == "workspace.create" }.count == 1)
    }

    @Test func closedMirrorReportsDetachedAndExplicitOpenRecreatesOnePendingRow() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = CatalogLocalFixture(), group = CatalogGroupFixture(), host = try host()
        let (catalog, mirrors) = catalog(directory, local: local, group: group, host: host)
        try await catalog.sync(host: host, workspaces: [.init(id: remoteWorkspace, title: "Agents")])
        let original = try #require(try await catalog.rows().first), seed = try #require(original.seed)
        await local.select(seed.workspaceID)
        _ = try await catalog.open(original.id, workspaceID: seed.workspaceID, surfaceID: seed.surfaceID)
        await local.close(seed.workspaceID)
        #expect(try await catalog.rows().first?.state == "paused")
        #expect(try await catalog.rows().first?.errorCode == "mirror_detached")
        await local.allowExplicitSelection()
        let reopened = try await catalog.select(hostID: host.id, workspaceID: remoteWorkspace)
        let replacement = try #require(try await catalog.rows().first), next = try #require(replacement.seed)
        #expect(replacement.id == original.id && next.workspaceID != seed.workspaceID)
        #expect(reopened["recreated"].bool == true && replacement.state == "pending")
        _ = try await catalog.open(original.id, workspaceID: next.workspaceID, surfaceID: next.surfaceID)
        #expect(await mirrors.list().count == 2)
        #expect(await mirrors.list().allSatisfy { $0.localWorkspaceID == next.workspaceID })
        _ = try await catalog.select(hostID: host.id, workspaceID: remoteWorkspace)
        #expect(await local.calls.filter { $0 == "workspace.create" }.count == 2)
    }
    @Test func movedPendingRowSelectsItsActualWindowWithoutCreatingAnotherWorkspace() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = CatalogLocalFixture(), group = CatalogGroupFixture(), host = try host()
        let (catalog, _) = catalog(directory, local: local, group: group, host: host)
        try await catalog.sync(host: host, workspaces: [.init(id: remoteWorkspace, title: "Agents")])
        let original = try #require(try await catalog.rows().first), seed = try #require(original.seed)
        let destination = "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB"
        await local.move(seed.workspaceID, window: destination); await local.allowExplicitSelection()
        _ = try await catalog.select(hostID: host.id, workspaceID: remoteWorkspace)
        #expect(await local.calls.filter { $0 == "workspace.create" }.count == 1)
        #expect(await local.selectionWindows == [destination])
        #expect(try await catalog.rows().first?.seed?.windowID == destination)
        #expect(try await catalog.wait(original.id) == false)
        try await catalog.refreshSelection()
        #expect(try await catalog.wait(original.id))
    }
    @Test func unfocusedNativeWindowIsNeverMistakenForAClosedMirror() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = CatalogLocalFixture(), group = CatalogGroupFixture(), host = try host()
        let (catalog, _) = catalog(directory, local: local, group: group, host: host)
        try await catalog.sync(host: host, workspaces: [.init(id: remoteWorkspace, title: "Agents")])
        let original = try #require(try await catalog.rows().first), seed = try #require(original.seed)
        await local.focusWindow("BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")
        #expect(try await catalog.rows().first?.state == "pending")
        await local.allowExplicitSelection()
        let opened = try await catalog.select(hostID: host.id, workspaceID: remoteWorkspace)
        #expect(opened["workspace_id"].string == seed.workspaceID)
        #expect(await local.calls.filter { $0 == "workspace.create" }.count == 1)
        #expect(await local.selectionWindows == [seed.windowID])
    }
    @Test func existingPausedMirrorIsPreservedAndLostRecreationCannotRepeat() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = CatalogLocalFixture(), group = CatalogGroupFixture(), host = try host()
        let (catalog, mirrors) = catalog(directory, local: local, group: group, host: host)
        try await catalog.sync(host: host, workspaces: [.init(id: remoteWorkspace, title: "Agents")])
        let row = try #require(try await catalog.rows().first), seed = try #require(row.seed)
        await local.select(seed.workspaceID)
        let view = try await catalog.open(row.id, workspaceID: seed.workspaceID, surfaceID: seed.surfaceID)
        try await mirrors.detach(view)
        #expect(try await catalog.rows().first?.state == "paused")
        await #expect(throws: BridgeError.self) { _ = try await catalog.select(hostID: host.id, workspaceID: remoteWorkspace) }
        #expect(await local.calls.filter { $0 == "workspace.create" }.count == 1)
        await local.close(seed.workspaceID); await local.loseNextCreate(); await local.allowExplicitSelection()
        for _ in 0..<2 {
            do { _ = try await catalog.select(hostID: host.id, workspaceID: remoteWorkspace); Issue.record("Expected unknown recreation") }
            catch { #expect((error as? BridgeError)?.code == "outcome_unknown") }
        }
        #expect(await local.calls.filter { $0 == "workspace.create" }.count == 2)
    }

    @Test func slowCreationPublicationCannotTriggerDuplicateRecreation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let local = CatalogLocalFixture(), group = CatalogGroupFixture(), host = try host()
        let (catalog, _) = catalog(directory, local: local, group: group, host: host)
        await local.delayNextTreePublication(reads: 100)
        await #expect(throws: BridgeError.self) { try await catalog.sync(host: host, workspaces: [.init(id: remoteWorkspace, title: "Agents")]) }
        for _ in 0..<2 {
            do { _ = try await catalog.select(hostID: host.id, workspaceID: remoteWorkspace); Issue.record("Expected publication wait") }
            catch { #expect((error as? BridgeError)?.code == "mirror_busy") }
        }
        #expect(await local.calls.filter { $0 == "workspace.create" }.count == 1)
        #expect(try await catalog.rows().first?.state == "pending")
    }

}

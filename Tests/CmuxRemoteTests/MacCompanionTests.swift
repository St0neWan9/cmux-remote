import Foundation
import Network
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteClient
import CmuxRemoteMac

private actor CompanionTestOwner: CmuxControlling {
    var calls: [String] = []
    var savedHostID: String?
    let discoveryHost: HostIdentity?
    var mirrorPauseCode: String?
    func pauseMirror(_ code: String) { mirrorPauseCode = code }
    init(savedHostID: String? = nil, discoveryHost: HostIdentity? = nil) { self.savedHostID = savedHostID; self.discoveryHost = discoveryHost }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        calls.append(method)
        if method == "mirror.workspace" { return .object(["workspace_id": .string("44444444-4444-4444-4444-444444444444")]) }
        if method == "mirror.status" { return .array([.object(["localWorkspaceID": .string("44444444-4444-4444-4444-444444444444"),
            "state": .string(mirrorPauseCode == nil ? "watching" : "paused"), "errorCode": mirrorPauseCode.map(JSONValue.string) ?? .null])]) }
        if method == "mac.forget" { savedHostID = nil; return .object(["removed": .bool(true)]) }
        if method == "mac.discovery.list", let discoveryHost {
            return try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode([
                MacDiscoveredHost(host: discoveryHost, serviceName: "Fixture", serviceType: "_cmux-remote._tcp.", serviceDomain: "local.")]))
        }
        if method == "mac.discovery.resolve" { return .object(["host": .string("127.0.0.1"), "port": .number(7740)]) }
        if method == "mac.enrollment.start" { return .object(["state": .string("connected")]) }
        if method == "mac.connections" { return .array(savedHostID.map { [.object(["id": .string($0), "name": .string("Saved host")])] } ?? []) }
        if method == "mac.workspaces", let savedHostID, params["host_id"]?.string == savedHostID {
            return .object(["workspaces": .array([.object(["id": .string("11111111-1111-1111-1111-111111111111"), "title": .string("Saved workspace")])])])
        }
        return .object(["workspaces": .array([])])
    }
}

@MainActor private final class CompanionTestDiscovery: MacBridgeDiscovering {
    private(set) var starts = 0
    private(set) var resolutions = 0
    func start() -> AsyncStream<[DiscoveredBridge]> { starts += 1; return AsyncStream { $0.finish() } }
    func stop() {}
    func resolve(_ discovered: DiscoveredBridge) async throws -> BridgeEndpoint { resolutions += 1; return .init(host: "127.0.0.1", port: 7740) }
}

@Suite struct MacCompanionTests {
    @Test @MainActor func backgroundMirrorPauseSurvivesUnrelatedWorkspaceRefresh() async throws {
        let owner = CompanionTestOwner(savedHostID: String(repeating: "a", count: 64))
        let model = MacCompanionModel(owner: owner, discovery: CompanionTestDiscovery()); defer { model.stop() }
        await model.open(hostID: String(repeating: "a", count: 64))
        await model.mirror(workspaceID: "11111111-1111-1111-1111-111111111111")
        #expect(model.mirrorErrorCode == nil)
        await owner.pauseMirror("mirror_local_changed"); await model.refreshMirrorStatus()
        await model.refreshWorkspaces()
        #expect(model.mirrorErrorCode == "mirror_local_changed")
        await model.forget(hostID: String(repeating: "a", count: 64))
        #expect(model.mirrorErrorCode == nil)
    }
    @Test @MainActor func forgettingSavedHostClearsItsSelectionWithoutRevokingRemoteDevices() async throws {
        let hostID = String(repeating: "a", count: 64)
        let owner = CompanionTestOwner(savedHostID: hostID)
        let model = MacCompanionModel(owner: owner, discovery: CompanionTestDiscovery())
        defer { model.stop() }
        await model.open(hostID: hostID); await model.forget(hostID: hostID)
        #expect(model.selectedHostID == nil); #expect(model.workspaces.isEmpty); #expect(model.connections.isEmpty)
        #expect(await owner.calls.contains("mac.forget")); #expect(await !owner.calls.contains("clients.revoke"))
    }
    @Test @MainActor func coldStartCanOpenSavedHostBeforeConnectionListWasLoaded() async throws {
        let hostID = String(repeating: "a", count: 64)
        let owner = CompanionTestOwner(savedHostID: hostID)
        let model = MacCompanionModel(owner: owner, discovery: CompanionTestDiscovery())
        defer { model.stop() }
        await model.open(hostID: hostID)
        #expect(model.selectedHostID == hostID)
        #expect(model.workspaces.first?["title"].string == "Saved workspace")
        #expect(await !owner.calls.contains("mac.enrollment.start"))
    }
    @Test @MainActor func disabledResidentDiscoveryDoesNotBrowseOnRefresh() async throws {
        let discovery = CompanionTestDiscovery()
        let resident = ResidentMacDiscovery(discovery: discovery, enabled: false)
        await resident.start(); await resident.refresh()
        #expect(discovery.starts == 0)
        #expect(try await resident.snapshot().isEmpty)
    }
    @Test @MainActor func residentDiscoveryCannotResolveAnUnobservedHost() async throws {
        let discovery = CompanionTestDiscovery()
        let guarded = ResidentMacDiscovery(discovery: discovery)
        await #expect(throws: BridgeError.self) { _ = try await guarded.resolve(hostID: String(repeating: "a", count: 64)) }
        #expect(discovery.resolutions == 0)
    }
    @Test @MainActor func ownerDiscoveryReadsHintsAndDelegatesOnlySelectedHostResolution() async throws {
        let crypto = IdentityCryptography(), key = try crypto.publicKey(privateKey: crypto.generatePrivateKey())
        let host = HostIdentity(id: try crypto.identityID(publicKey: key), publicKey: key, certificateSHA256: String(repeating: "b", count: 64), name: "Fixture")
        let owner = CompanionTestOwner(discoveryHost: host)
        let shared = OwnerBridgeDiscovery(owner: owner)
        defer { shared.stop() }
        var iterator = shared.start().makeAsyncIterator()
        let devices = try #require(await iterator.next())
        #expect(devices.count == 1); #expect(devices.first?.host == host)
        let endpoint = try await shared.resolve(#require(devices.first))
        #expect(endpoint == BridgeEndpoint(host: "127.0.0.1", port: 7740))
        #expect(await owner.calls == ["mac.discovery.refresh", "mac.discovery.list", "mac.discovery.resolve"])
    }
    @Test @MainActor func refreshRestartsDiscoveryAndKeepsSavedWorkspaceUsable() async throws {
        let hostID = String(repeating: "a", count: 64)
        let owner = CompanionTestOwner(savedHostID: hostID)
        let discovery = CompanionTestDiscovery()
        let model = MacCompanionModel(owner: owner, discovery: discovery)
        defer { model.stop() }
        await model.refreshConnections(); await model.open(hostID: hostID)
        let initial = discovery.starts
        await model.refresh()
        #expect(discovery.starts == initial + 1)
        #expect(model.workspaces.first?["title"].string == "Saved workspace")
        #expect(await !owner.calls.contains("mac.enrollment.cancel"))
    }
    @Test @MainActor func savedHostRemainsSelectableWithoutBonjourResults() async throws {
        let hostID = String(repeating: "a", count: 64)
        let owner = CompanionTestOwner(savedHostID: hostID)
        let model = MacCompanionModel(owner: owner, discovery: CompanionTestDiscovery())
        defer { model.stop() }
        await model.refreshConnections()
        await model.open(hostID: hostID)
        #expect(model.devices.isEmpty)
        #expect(model.selectedHostID == hostID)
        #expect(model.workspaces.first?["title"].string == "Saved workspace")
        #expect(await owner.calls.contains("mac.workspaces"))
        #expect(await !owner.calls.contains("mac.enrollment.start"))
    }
    @Test @MainActor func discoverySelectionCannotEnrollUntilIdentityIsConfirmed() async throws {
        let owner = CompanionTestOwner()
        let model = MacCompanionModel(owner: owner, discovery: CompanionTestDiscovery())
        let crypto = IdentityCryptography(); let key = try crypto.publicKey(privateKey: crypto.generatePrivateKey())
        let host = HostIdentity(id: try crypto.identityID(publicKey: key), publicKey: key, certificateSHA256: String(repeating: "b", count: 64), name: "Fixture")
        let device = DiscoveredBridge(host: host, service: .service(name: "Fixture", type: "_cmux-remote._tcp", domain: "local.", interface: nil))
        await model.select(device)
        #expect(model.trustCandidate?.host.id == host.id)
        #expect(await owner.calls.isEmpty)
        model.declineTrust()
        #expect(model.trustCandidate == nil); #expect(await owner.calls.isEmpty)
        await model.select(device); await model.confirmTrust(device)
        #expect(await owner.calls.filter { $0 == "mac.enrollment.start" }.count == 1)
    }
}

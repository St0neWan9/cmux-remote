import Foundation
import Observation
import CmuxRemoteClient
import CmuxRemoteCore
import CmuxRemoteBridge

/// Companion navigation over owner-only commands; UI never owns network authorization state.
@MainActor @Observable public final class MacCompanionModel {
    public private(set) var devices: [DiscoveredBridge] = []
    public private(set) var connections: [JSONValue] = []
    public private(set) var workspaces: [JSONValue] = []
    public private(set) var selectedHostID: String?
    public private(set) var trustCandidate: DiscoveredBridge?
    public private(set) var pendingRequestID: String?
    public private(set) var busy = false
    public private(set) var errorCode: String?
    public private(set) var mirroredWorkspaceID: String?
    public private(set) var mirrorErrorCode: String?
    private let owner: any CmuxControlling
    private let discovery: any MacBridgeDiscovering
    private var discoveryTask: Task<Void, Never>?
    private var discoveryObservationID: UUID?
    private var enrollmentTask: Task<Void, Never>?
    private var requestedHostID: String?
    public init(owner: any CmuxControlling, discovery: any MacBridgeDiscovering) { self.owner = owner; self.discovery = discovery }
    public func start() {
        guard discoveryTask == nil else { return }
        observeDiscovery()
        Task { await refreshConnections() }
    }
    private func observeDiscovery() {
        let observationID = UUID(); discoveryObservationID = observationID
        let changes = discovery.start()
        discoveryTask = Task { [weak self] in
            for await devices in changes {
                guard let self, self.discoveryObservationID == observationID else { return }; self.devices = devices
                await self.refreshMirrorStatus()
                if let requested = self.requestedHostID, let device = devices.first(where: { $0.host.id == requested }) {
                    self.requestedHostID = nil; await self.select(device)
                }
            }
            if let self, self.discoveryObservationID == observationID { self.discoveryTask = nil }
        }
    }
    /// Restarts a failed or background-started browse without cancelling enrollment.
    public func refresh() async {
        discoveryObservationID = nil; discoveryTask?.cancel(); discoveryTask = nil; discovery.stop(); devices = []
        observeDiscovery()
        await refreshConnections(); await refreshWorkspaces(); await refreshMirrorStatus()
    }
    public func stop() { discoveryObservationID = nil; discoveryTask?.cancel(); discoveryTask = nil; discovery.stop(); enrollmentTask?.cancel(); enrollmentTask = nil }
    public func open(hostID: String) async {
        start()
        guard !busy else { return }
        if let device = devices.first(where: { $0.host.id == hostID }) { await select(device) }
        else {
            // A cold URL open can precede the start task's saved-state read.
            if !connections.contains(where: { $0["id"].string == hostID }) { await refreshConnections() }
            guard !busy else { return }
            if let device = devices.first(where: { $0.host.id == hostID }) { await select(device) }
            else if connections.contains(where: { $0["id"].string == hostID }) {
                requestedHostID = nil; selectedHostID = hostID; await refreshWorkspaces()
            } else { requestedHostID = hostID }
        }
    }
    public func refreshConnections() async {
        do { connections = try await owner.request("mac.connections", params: [:]).array ?? []; errorCode = nil }
        catch { errorCode = (error as? BridgeError)?.code ?? "connection_failed" }
    }
    public func select(_ device: DiscoveredBridge) async {
        guard !busy else { return }
        selectedHostID = device.host.id; workspaces = []; mirroredWorkspaceID = nil; mirrorErrorCode = nil
        if connections.contains(where: { $0["id"].string == device.host.id }) { await connect(device) }
        else { trustCandidate = device }
    }
    public func confirmTrust(_ device: DiscoveredBridge) async {
        trustCandidate = nil; await connect(device)
    }
    public func declineTrust() { trustCandidate = nil }
    public func refreshWorkspaces() async {
        guard let selectedHostID else { return }
        do { workspaces = try await owner.request("mac.workspaces", params: ["host_id": .string(selectedHostID)])["workspaces"].array ?? []; errorCode = nil }
        catch { errorCode = (error as? BridgeError)?.code ?? "connection_failed" }
    }
    public func mirror(workspaceID: String) async {
        guard let selectedHostID, !busy else { return }; busy = true; defer { busy = false }
        do {
            let result = try await owner.request("mirror.workspace", params: ["host_id": .string(selectedHostID), "workspace_id": .string(workspaceID)])
            mirroredWorkspaceID = result["workspace_id"].string; errorCode = nil
            await refreshMirrorStatus()
        } catch { errorCode = (error as? BridgeError)?.code ?? "connection_failed" }
    }
    /// Presents synchronization failures separately from enrollment/network errors.
    public func refreshMirrorStatus() async {
        guard let mirroredWorkspaceID else { mirrorErrorCode = nil; return }
        do {
            let statuses = try await owner.request("mirror.status", params: [:])
            guard let rows = statuses.array, rows.count <= 4096 else { throw BridgeError("invalid_response", "Invalid mirror status.") }
            mirrorErrorCode = rows.first { $0["localWorkspaceID"].string == mirroredWorkspaceID && ["paused", "reconnecting"].contains($0["state"].string ?? "") }?["errorCode"].string
        } catch { mirrorErrorCode = (error as? BridgeError)?.code ?? "connection_failed" }
    }
    /// Forgets only this Mac's saved trust; host-side revocation remains a separate owner action.
    public func forget(hostID: String) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            _ = try await owner.request("mac.forget", params: ["host_id": .string(hostID)])
            if selectedHostID == hostID { selectedHostID = nil; workspaces = []; mirroredWorkspaceID = nil; mirrorErrorCode = nil }
            await refreshConnections(); errorCode = nil
        } catch { errorCode = (error as? BridgeError)?.code ?? "connection_failed" }
    }
    public func cancelEnrollment() async {
        enrollmentTask?.cancel(); enrollmentTask = nil
        _ = try? await owner.request("mac.enrollment.cancel", params: [:]); pendingRequestID = nil; busy = false
    }
    private func connect(_ device: DiscoveredBridge) async {
        busy = true; errorCode = nil
        do {
            let endpoint = try await discovery.resolve(device)
            let encoder = JSONEncoder()
            let result = try await owner.request("mac.enrollment.start", params: [
                "host": try JSONDecoder().decode(JSONValue.self, from: encoder.encode(device.host)),
                "endpoint": try JSONDecoder().decode(JSONValue.self, from: encoder.encode(endpoint)),
                "trust_confirmed": .bool(true), "name": .string(Host.current().localizedName ?? "Mac Companion")])
            if result["state"].string == "connected" { busy = false; await refreshConnections(); await refreshWorkspaces(); return }
            pendingRequestID = result["requestID"].string
            enrollmentTask?.cancel()
            enrollmentTask = Task { [weak self] in
                guard let self else { return }
                do {
                    while !Task.isCancelled {
                        // Owner-approval observation cadence, cancelled when the user dismisses enrollment.
                        try await Task.sleep(for: .seconds(2))
                        let status = try await self.owner.request("mac.enrollment.status", params: [:])
                        if status["state"].string == "approved" {
                            self.pendingRequestID = nil; self.busy = false; await self.refreshConnections(); await self.refreshWorkspaces(); return
                        }
                        if ["denied", "expired", "cancelled"].contains(status["state"].string ?? "") {
                            throw BridgeError("enrollment_" + (status["state"].string ?? "denied"), "Enrollment did not complete.")
                        }
                    }
                } catch is CancellationError {} catch {
                    self.errorCode = (error as? BridgeError)?.code ?? "connection_failed"; self.pendingRequestID = nil; self.busy = false
                }
            }
        } catch { errorCode = (error as? BridgeError)?.code ?? "connection_failed"; busy = false }
    }
}

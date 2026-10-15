import Foundation
import Observation
import CmuxRemoteCore
import CmuxRemoteClient

/// One "new session" flow on one Mac: folders inside an approved workspace, then a fixed agent.
@MainActor @Observable
final class StartSessionModel {
    let hostID: String
    let workspace: WorkspaceSummary
    private(set) var roots: [LaunchDirectory] = []
    private(set) var loading = false
    private(set) var starting = false
    /// The last start's result is unknown; repeating the same choice asks the Mac what happened.
    private(set) var uncertain = false
    var error: String?
    var agent: LaunchAgent = .claude
    private var pendingRequest: StartSessionRequest?
    private let client: RemoteClient

    init(hostID: String, workspace: WorkspaceSummary, client: RemoteClient) {
        self.hostID = hostID; self.workspace = workspace; self.client = client
    }

    func loadRoots() async {
        loading = true; defer { loading = false }
        do { roots = try await client.get("/v1/workspaces/\(workspace.id)/directories", as: [LaunchDirectory].self); error = nil }
        catch { self.error = ErrorPresentation().message(error) }
    }

    func listing(root: LaunchDirectory, path: String) async throws -> LaunchDirectoryListing {
        try await client.get("/v1/workspaces/\(workspace.id)/directories/\(root.id)", query: path.isEmpty ? [:] : ["path": path], as: LaunchDirectoryListing.self)
    }

    /// Returns whether cmux opened the terminal and, for a fresh start, its surface.
    /// The same choice after an unknown outcome reuses its identity, so the Mac answers instead of opening another;
    /// `fresh` deliberately opens another terminal.
    func start(root: LaunchDirectory, path: String, agent: LaunchAgent, fresh: Bool = false) async -> (accepted: Bool, surfaceID: String?) {
        guard !starting else { return (false, nil) }
        starting = true; defer { starting = false }
        let same = pendingRequest.map { $0.rootID == root.id && $0.path == path && $0.agent == agent } ?? false
        let request = same && !fresh ? pendingRequest! : StartSessionRequest(rootID: root.id, path: path, agent: agent)
        pendingRequest = request
        do {
            let receipt = try await client.post("/v1/workspaces/\(workspace.id)/sessions", body: request, as: StartSessionReceipt.self)
            pendingRequest = nil; uncertain = false; error = nil
            return (receipt.accepted, receipt.surfaceID)
        } catch {
            let code = (error as? BridgeError)?.code
            uncertain = code == "outcome_unknown"
            if !uncertain { pendingRequest = nil }
            self.error = switch code {
            case "outcome_unknown": String(localized: "start.outcome_unknown")
            case "stale_binding": String(localized: "start.folder_gone")
            default: ErrorPresentation().message(error)
            }
            return (false, nil)
        }
    }
}

/// Navigation identity is the model instance.
extension StartSessionModel: Hashable {
    nonisolated static func == (lhs: StartSessionModel, rhs: StartSessionModel) -> Bool { lhs === rhs }
    nonisolated func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}

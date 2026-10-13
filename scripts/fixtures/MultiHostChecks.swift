import Foundation
import CmuxRemoteCore
import CmuxRemoteClient

/// Several approved Macs on one phone: combined lists, per-Mac failures, removal and relay directories.
enum MultiHostChecks {
    @MainActor static func run() async -> (count: Int, failures: [String]) {
        var count = 0, failures: [String] = []
        func check(_ condition: Bool, _ message: String) { count += 1; if !condition { failures.append(message) } }
        func client(_ port: Int) -> RemoteClient {
            RemoteClient(pairing: try! PairingConfiguration(host: "localhost", port: port, token: String(repeating: "0", count: 32), certificateSHA256: String(repeating: "0", count: 64)))
        }
        let studio = client(1), laptop = client(2)
        defer { studio.close(); laptop.close() }
        let session: @Sendable (String) -> SessionDescriptor = { SessionDescriptor(id: $0, agent: "claude", title: $0, cwd: nil, workspaceID: "workspace-" + $0, surfaceID: "surface", state: "idle") }
        let laptopFails = FailureSwitch()
        let model = AppModel(fetchSessions: { client in
            if client === laptop { if await laptopFails.on { throw URLError(.timedOut) }; return [session("same-id"), session("laptop")] }
            return [session("same-id")]
        }, fetchWorkspaces: { client in [WorkspaceSummary(id: client === laptop ? "laptop-workspace" : "studio-workspace", title: "Workspace")] },
        directory: { origin in
            if origin.contains("down") { throw URLError(.cannotConnectToHost) }
            return []
        })
        model.links = [HostLink(id: "studio", name: "Studio", client: studio, connection: nil), HostLink(id: "laptop", name: "Laptop", client: laptop, connection: nil)]
        await model.refresh()
        check(model.hostedSessions.map(\.id) == ["studio:same-id", "laptop:laptop", "laptop:same-id"], "Combined list lost Mac order or merged equal session IDs from two Macs")
        check(model.workspaceHosts["laptop-workspace"] == "Laptop" && model.workspaces.count == 2, "Workspaces lost the Mac that owns them")
        await laptopFails.set(true); await model.refresh()
        check(model.hostedSessions.count == 3 && model.hostErrors["laptop"] != nil && model.hostErrors["studio"] == nil, "One unreachable Mac hid its last list or blamed another Mac")
        check(model.error?.hasPrefix("Laptop") == true, "The combined error did not name the failing Mac")
        model.remove(hostID: "laptop")
        check(model.hostedSessions.map(\.id) == ["studio:same-id"] && model.hostErrors["laptop"] == nil && model.links.map(\.id) == ["studio"], "Removing one Mac left its conversations or errors behind")
        model.relayOrigins = ["https://down.example", "https://up.example"]
        await model.refreshRelayDirectory()
        check(model.relayHosts.isEmpty && model.relayError == ErrorPresentation().message(URLError(.cannotConnectToHost)), "An empty working relay hid the failing relay's error")
        check(model.isApproved("studio") && !model.isApproved("laptop"), "Approved-Mac lookup does not follow removal")
        return (count, failures)
    }
}

private actor FailureSwitch {
    private(set) var on = false
    func set(_ value: Bool) { on = value }
}

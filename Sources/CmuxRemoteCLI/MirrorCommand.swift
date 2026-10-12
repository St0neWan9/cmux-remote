import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteMac

/// Thin owner-side entrypoint; no remote credentials enter argv or terminal output.
struct MirrorCommand {
    func run(options: CLIOptions, state: BridgeState) async throws {
        let owner = UnixSocketClient(path: state.directory.appendingPathComponent("owner.sock").path)
        switch options.args.first {
        case "pending":
            guard let raw = options.value("entry"), let id = UUID(uuidString: raw),
                  let ws = ProcessInfo.processInfo.environment["CMUX_WORKSPACE_ID"], let surface = ProcessInfo.processInfo.environment["CMUX_SURFACE_ID"] else {
                throw BridgeError("invalid_input", "Run pending entries only in their created native terminals.")
            }
            try await NativeCatalogTerminalSession(owner: owner).run(entryID: id, workspaceID: ws, surfaceID: surface)
        case "catalog":
            let result = try await owner.request("mirror.catalog.list")
            print(String(decoding: try JSONEncoder().encode(result), as: UTF8.self))
        case "view":
            guard let raw = options.value("projection"), let id = UUID(uuidString: raw) else { throw BridgeError("invalid_input", "Choose a projection UUID.") }
            try await TerminalViewer(owner: owner).run(projectionID: id)
        case "workspace", "sync":
            let host = options.value("host") ?? (options.args.count > 1 ? options.args[1] : nil)
            let workspace = options.value("workspace") ?? (options.args.count > 2 ? options.args[2] : nil)
            guard let host, let workspace else { throw BridgeError("invalid_input", "Use mirror workspace --host ID --workspace UUID.") }
            let method = options.args.first == "sync" ? "mirror.sync" : "mirror.workspace"
            let result = try await owner.request(method, params: ["host_id": .string(host), "workspace_id": .string(workspace)])
            print(String(decoding: try JSONEncoder().encode(result), as: UTF8.self))
        case "list":
            let result = try await owner.request("mirror.list")
            print(String(decoding: try JSONEncoder().encode(result), as: UTF8.self))
        case "status":
            let result = try await owner.request("mirror.status")
            print(String(decoding: try JSONEncoder().encode(result), as: UTF8.self))
        default: throw BridgeError("invalid_input", "Use mirror workspace, mirror sync, mirror status, mirror list, or mirror view.")
        }
    }
}

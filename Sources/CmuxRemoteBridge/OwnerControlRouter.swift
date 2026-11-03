import Foundation
import CmuxRemoteCore

/// Local owner commands require access to the owner-only Unix socket, never a network grant.
struct OwnerControlRouter: Sendable {
    let authority: ConnectionAuthority
    let service: SessionService
    var mac: (any LocalMacControlling)? = nil
    var sharing: ManagedSharingService? = nil
    /// The owner's shared project folders, off unless the resident Bridge keeps them.
    var allowedDirectories: AllowedDirectoryRepository? = nil
    func respond(_ request: JSONValue) async -> JSONValue {
        let id = request["id"]
        do {
            let params = request["params"]
            let value: JSONValue
            switch request["method"].string {
            case "bridge.status", "bridge.start", "bridge.stop":
                guard let sharing else { throw BridgeError("sharing_unsupported", "Upgrade the resident Bridge to manage sharing.") }
                switch request["method"].string {
                case "bridge.start": value = try await sharing.start(port: params["port"].int)
                case "bridge.stop": value = await sharing.stop()
                default: value = await sharing.status()
                }
            case "relay.configure":
                guard let sharing else { throw BridgeError("sharing_unsupported", "Upgrade the Bridge to configure relay access.") }
                value = try await sharing.configureRelay(origin: params["origin"].string, keyFile: params["key_file"].string)
            case "directories.allowed":
                guard let store = allowedDirectories else { throw BridgeError("sharing_unsupported", "Upgrade the resident Bridge to choose allowed folders.") }
                value = .object(["directories": .array(store.load().map { .string(display($0)) })])
            case "directories.set_allowed":
                guard let store = allowedDirectories else { throw BridgeError("sharing_unsupported", "Upgrade the resident Bridge to choose allowed folders.") }
                guard let chosen = params["directories"].array else { throw BridgeError("invalid_input", "Choose the folders to allow.", status: 422) }
                try store.save(chosen.compactMap(\.string))
                value = .object(["directories": .array(store.load().map { .string(display($0)) })])
            case "bridge.workspaces": value = try await service.workspaces()
            case "enrollment.open":
                guard let host = params["host"].string, let port = params["port"].int else { throw BridgeError("invalid_input", "Choose the host endpoint.") }
                let available = try await service.workspaces()["workspaces"].array ?? []
                let existingIDs = Set(available.compactMap { $0["id"].string?.lowercased() })
                let chosen = params["workspaces"].array?.compactMap(\.string).map { $0.lowercased() } ?? Array(existingIDs)
                guard Set(chosen).isSubset(of: existingIDs) else { throw BridgeError("invalid_scope", "Choose current cmux workspaces.") }
                value = try json(await authority.open(endpoint: BridgeEndpoint(host: host, port: port), workspaces: chosen, seconds: params["seconds"].int ?? 300))
            case "enrollment.close": await authority.closeEnrollment(); value = .object(["closed": .bool(true)])
            case "enrollment.pending": value = try json(await authority.pendingRequests())
            case "enrollment.approve":
                guard let requestID = params["request_id"].string, let scopeJSON = params["scope"].object else { throw BridgeError("invalid_input", "Approve an exact request and explicit scope.") }
                let scope = try JSONDecoder().decode(ClientScope.self, from: JSONEncoder().encode(JSONValue.object(scopeJSON)))
                let available = try await service.workspaces()["workspaces"].array ?? []
                let IDs = Set(available.compactMap { $0["id"].string?.lowercased() })
                guard Set(scope.workspaces).isSubset(of: IDs) else { throw BridgeError("invalid_scope", "The selected workspace no longer exists.") }
                try await authority.approve(requestID: requestID, scope: scope); value = .object(["approved": .bool(true)])
            case "enrollment.deny":
                guard let requestID = params["request_id"].string else { throw BridgeError("invalid_input", "Choose an exact request.") }
                try await authority.deny(requestID: requestID); value = .object(["denied": .bool(true)])
            case "clients.list": value = try json(await authority.enrolledClients())
            case "clients.revoke":
                guard let clientID = params["client_id"].string else { throw BridgeError("invalid_input", "Choose an exact client.") }
                try await authority.revoke(clientID: clientID); value = .object(["revoked": .bool(true)])
            default:
                guard let method = request["method"].string, method.hasPrefix("mac.") || method.hasPrefix("mirror."), let mac else {
                    throw BridgeError("not_found", "Unknown owner operation.", status: 404)
                }
                value = try await mac.request(method, params: params)
            }
            return .object(["id": id, "ok": .bool(true), "result": value])
        } catch {
            var failure = (error as? BridgeError) ?? BridgeError("invalid_request", "The owner request could not be processed.")
            if request["method"].string == "mirror.replay", failure.code == "mirror_remote_unavailable" {
                // Existing viewers recognize this read-only reconnect code.
                // Preserve them across a Bridge upgrade; never alias writes.
                failure = BridgeError("socket_unavailable", failure.message, status: 503)
            }
            return .object(["id": id, "ok": .bool(false), "error": .object(["code": .string(failure.code), "message": .string(failure.message)])])
        }
    }
    private func json<T: Encodable>(_ value: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) }
    /// The home directory shows as `~` wherever a folder is named.
    private func display(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home + "/") ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

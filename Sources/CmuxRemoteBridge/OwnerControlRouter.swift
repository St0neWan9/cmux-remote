import Foundation
import CmuxRemoteCore

/// Local owner commands require access to the owner-only Unix socket, never a network grant.
struct OwnerControlRouter: Sendable {
    let authority: ConnectionAuthority
    let service: SessionService
    func respond(_ request: JSONValue) async -> JSONValue {
        let id = request["id"]
        do {
            let params = request["params"]
            let value: JSONValue
            switch request["method"].string {
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
            default: throw BridgeError("not_found", "Unknown owner operation.", status: 404)
            }
            return .object(["id": id, "ok": .bool(true), "result": value])
        } catch {
            let failure = (error as? BridgeError) ?? BridgeError("invalid_request", "The owner request could not be processed.")
            return .object(["id": id, "ok": .bool(false), "error": .object(["code": .string(failure.code), "message": .string(failure.message)])])
        }
    }
    private func json<T: Encodable>(_ value: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) }
}

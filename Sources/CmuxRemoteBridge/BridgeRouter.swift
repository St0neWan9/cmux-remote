import Foundation
import CmuxRemoteCore

/// A fixed resource router; never forwards caller-selected RPC methods.
public struct BridgeRouter: Sendable {
    private let service: SessionService
    private let token: String
    public init(service: SessionService, token: String) { self.service = service; self.token = token }
    public func respond(method: String, uri: String, authorization: String?, body: Data) async -> (Int, Data) {
        do {
            guard constantTimeEqual(authorization ?? "", "Bearer " + token) else { throw BridgeError("unauthorized", "Pair this device to continue.", status: 401) }
            guard body.count <= 1_048_576 else { throw BridgeError("too_large", "The request is too large.", status: 413) }
            guard let components = URLComponents(string: uri), components.scheme == nil, components.host == nil else { throw BridgeError("invalid_route", "Invalid resource path.") }
            let path = components.path.split(separator: "/").map(String.init)
            let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
            let data: Data
            if method == "GET", path == ["v1", "status"] { data = try encode(await service.status()) }
            else if method == "GET", path == ["v1", "workspaces"] { data = try encode(await service.workspaces()) }
            else if method == "GET", path == ["v1", "sessions"] { data = try encode(await service.sessions()) }
            else if method == "GET", path == ["v1", "feed"] { data = try encode(await service.feed()) }
            else if path.count == 4, path[0...1] == ["v1", "sessions"] {
                let id = path[2]
                switch (method, path[3]) {
                case ("GET", "history"): data = try encode(await service.history(id: id, beforeSeq: query["before_seq"].flatMap(Int.init), limit: query["limit"].flatMap(Int.init) ?? 100))
                case ("GET", "preview"): data = try encode(await service.preview(id: id))
                case ("GET", "changes"): data = try encode(await service.changes(id: id))
                case ("GET", "diff"): data = try encode(await service.diff(id: id, path: query["path"]))
                case ("GET", "file"):
                    guard let relative = query["path"] else { throw BridgeError("invalid_input", "A relative file path is required.") }
                    data = try encode(await service.file(id: id, path: relative))
                case ("POST", "send"): data = try encode(await service.send(id: id, request: JSONDecoder().decode(SendRequest.self, from: body)))
                case ("POST", "interrupt"): data = try encode(await service.interrupt(id: id, request: JSONDecoder().decode(InterruptRequest.self, from: body)))
                default: throw BridgeError("not_found", "This resource is not available.", status: 404)
                }
            } else if method == "POST", path.count == 4, path[0...1] == ["v1", "feed"], path[3] == "reply" {
                data = try encode(await service.reply(requestID: path[2], body: JSONDecoder().decode(JSONValue.self, from: body)))
            } else { throw BridgeError("not_found", "This resource is not available.", status: 404) }
            return (200, data)
        } catch {
            let failure = (error as? BridgeError) ?? BridgeError("invalid_request", "The request could not be processed.")
            return (failure.status, (try? encode(["error": failure])) ?? Data())
        }
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }
    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let left = Array(a.utf8); let right = Array(b.utf8)
        var difference = left.count ^ right.count
        for index in 0..<max(left.count, right.count) { difference |= Int((index < left.count ? left[index] : 0) ^ (index < right.count ? right[index] : 0)) }
        return difference == 0
    }
}

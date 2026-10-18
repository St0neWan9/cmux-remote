import Foundation
import CmuxRemoteCore

/// Fixed scoped resources and public enrollment routes. Owner approval is never exposed over HTTPS.
public struct BridgeRouter: Sendable {
    private let service: SessionService
    private let legacyToken: String?
    private let authority: ConnectionAuthority?
    private let mirrors: RemoteMirrorService?
    private let launcher: SessionLauncher?
    /// An explicitly selected legacy router, retained for migration and fixtures.
    /// A fixture's launcher acts with owner authority, since the legacy token is the owner's own.
    public init(service: SessionService, token: String, launcher: SessionLauncher? = nil) { self.service = service; legacyToken = token; authority = nil; mirrors = nil; self.launcher = launcher }
    public init(service: SessionService, authority: ConnectionAuthority, legacyToken: String? = nil, mirrors: RemoteMirrorService? = nil, launcher: SessionLauncher? = nil) {
        self.service = service; self.authority = authority; self.legacyToken = legacyToken; self.mirrors = mirrors; self.launcher = launcher
    }
    public func respond(method: String, uri: String, authorization: String?, body: Data) async -> (Int, Data) {
        let response = await respondResource(method: method, uri: uri, authorization: authorization, body: body)
        return (response.status, response.data)
    }
    var linkAuthority: ConnectionAuthority? { authority }
    /// Prevents a signed request from borrowing another authenticated link identity.
    func verifyChannelIdentity(_ frame: LinkFrame, clientID: String) throws {
        if frame.uri == "/v2/identity" || frame.uri == "/v2/enrollment/bootstrap" { return }
        if frame.uri?.hasPrefix("/v2/enrollment/") == true {
            let signed = try JSONDecoder().decode(SignedValue<EnrollmentRequest>.self, from: frame.data ?? Data())
            guard signed.value.clientID == clientID else { throw BridgeError("unauthorized", "The enrollment belongs to another device.", status: 401) }
        } else {
            guard let header = frame.authorization, header.hasPrefix("CmuxV2 "), header.utf8.count <= 4096,
                  let data = Data(base64Encoded: String(header.dropFirst(7))),
                  let proof = try? JSONDecoder().decode(SignedValue<RequestProof>.self, from: data), proof.value.clientID == clientID else { throw BridgeError("unauthorized", "The request belongs to another device.", status: 401) }
        }
    }
    func subscriptionIdentity(_ frame: LinkFrame, clientID: String) async throws -> String {
        guard frame.method == "GET", let uri = frame.uri, let authority, isSubscriptionURI(uri) else { throw BridgeError("invalid_route", "This resource cannot be subscribed.") }
        let client = try await authority.authorize(header: frame.authorization, method: "GET", uri: uri, body: Data())
        guard client.id == clientID else { throw BridgeError("unauthorized", "The subscription belongs to another device.", status: 401) }
        return client.id
    }
    private func isSubscriptionURI(_ uri: String) -> Bool { LinkSubscriptionResource(uri: uri) != nil }
    /// What one subscription tick would answer, when that is provable without running the handler; nil
    /// means run it. The device's grant and the session's workspace are checked here as on the handler
    /// path, so a refusal is never hidden behind a skipped tick: a failed check runs the handler, which
    /// answers the refusal exactly as before.
    func subscriptionStamp(uri: String, clientID: String) async -> String? {
        guard let authority, let resource = LinkSubscriptionResource(uri: uri),
              let current = await service.subscriptionStamp(resource),
              (try? await authority.require(clientID, capability: .conversationRead, workspace: current.workspace)) != nil else { return nil }
        return current.stamp
    }
    func respondResource(method: String, uri: String, authorization: String?, body: Data, subscriptionClientID: String? = nil) async -> HTTPResourceResponse {
        do {
            guard body.count <= 1_048_576 else { throw BridgeError("too_large", "The request is too large.", status: 413) }
            guard let components = URLComponents(string: uri), components.scheme == nil, components.host == nil else { throw BridgeError("invalid_route", "Invalid resource path.") }
            var path = components.path.split(separator: "/").map(String.init)
            let query = Dictionary((components.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
            let client: EnrolledClient?
            if path.first == "v2", let authority {
                if method == "GET", path == ["v2", "identity"] { return HTTPResourceResponse.json(try encode(await authority.announcement())) }
                if method == "GET", path == ["v2", "enrollment", "bootstrap"] { return HTTPResourceResponse.json(try encode(await authority.bootstrap())) }
                if method == "POST", path.count == 3, path[1] == "enrollment" {
                    let request = try JSONDecoder().decode(SignedValue<EnrollmentRequest>.self, from: body)
                    switch path[2] {
                    case "request": return HTTPResourceResponse.json(try encode(await authority.submit(request)))
                    case "status": return HTTPResourceResponse.json(try encode(await authority.status(request)))
                    case "cancel": return HTTPResourceResponse.json(try encode(await authority.cancel(request)))
                    default: throw BridgeError("not_found", "This enrollment resource is unavailable.", status: 404)
                    }
                }
                if let subscriptionClientID {
                    guard method == "GET", isSubscriptionURI(uri), body.isEmpty else { throw BridgeError("invalid_route", "Invalid subscription read.") }
                    client = try await authority.currentClient(subscriptionClientID)
                } else { client = try await authority.authorize(header: authorization, method: method, uri: uri, body: body) }
                path[0] = "v1"
            } else {
                guard path.first == "v1", let legacyToken, constantTimeEqual(authorization ?? "", "Bearer " + legacyToken) else { throw BridgeError("unauthorized", "Enroll this device to continue. Legacy pairing is disabled unless explicitly enabled.", status: 401) }
                client = nil
            }
            let access: SessionAccess?
            if let client, let authority {
                access = SessionAccess(clientID: client.id, checkAll: { capabilities, workspace in _ = try await authority.require(client.id, capabilities: capabilities, workspace: workspace) }) { capability, workspace in _ = try await authority.require(client.id, capability: capability, workspace: workspace) }
            } else { access = nil }
            let data: Data
            var image = false
            if method == "GET", path == ["v1", "relay"] {
                guard let authority, let client else { throw BridgeError("unauthorized", "Relay hints require an enrolled device.", status: 401) }
                return HTTPResourceResponse.json(try encode(await authority.relayHint(clientID: client.id)))
            }
            if path.count == 4, path[0...1] == ["v1", "workspaces"], path[3] == "mirror", method == "GET" {
                guard let client, let authority, let mirrors else { throw BridgeError("mirror_unsupported", "Terminal mirroring requires scoped v2 enrollment and a mirror-enabled Bridge.", status: 422) }
                _ = try await authority.require(client.id, capability: .terminalRead, workspace: path[2])
                let snapshot = try await mirrors.workspace(id: path[2])
                _ = try await authority.require(client.id, capability: .terminalRead, workspace: path[2])
                return HTTPResourceResponse.json(try encode(snapshot))
            }
            if path.count == 6, path[0...1] == ["v1", "workspaces"], path[3] == "terminals" {
                guard let client, let authority, let mirrors else { throw BridgeError("mirror_unsupported", "Terminal mirroring requires scoped v2 enrollment and a mirror-enabled Bridge.", status: 422) }
                let workspace = path[2]; let surface = path[4]
                if method == "GET", path[5] == "replay" {
                    _ = try await authority.require(client.id, capability: .terminalRead, workspace: workspace)
                    var snapshot = try await mirrors.replay(workspaceID: workspace, surfaceID: surface)
                    let approved = try await authority.require(client.id, capability: .terminalRead, workspace: workspace)
                    snapshot.allowsInput = approved.scope.capabilities.contains(.terminalInput)
                    return HTTPResourceResponse.json(try encode(snapshot))
                }
                if method == "POST", path[5] == "input" {
                    _ = try await authority.require(client.id, capability: .terminalInput, workspace: workspace)
                    let input = try JSONDecoder().decode(MirrorInputRequest.self, from: body)
                    let receipt = try await mirrors.input(workspaceID: workspace, surfaceID: surface, clientID: client.id, request: input) {
                        _ = try await authority.require(client.id, capability: .terminalInput, workspace: workspace)
                    }
                    return HTTPResourceResponse.json(try encode(receipt))
                }
                throw BridgeError("not_found", "Unknown terminal mirror operation.", status: 404)
            }
            // Starting a session: folders inside one approved workspace, then a fixed agent command in a new terminal.
            if path.count >= 4, path.count <= 5, path[0...1] == ["v1", "workspaces"], ["directories", "sessions"].contains(path[3]) {
                // A production router always has an authority, so a legacy token never starts sessions there.
                let owner = authority == nil ? SessionAccess(clientID: "owner") { _, _ in } : nil
                guard let access = access ?? owner, let launcher else { throw BridgeError("launch_unsupported", "Starting sessions requires scoped v2 enrollment and a current Bridge.", status: 422) }
                let workspace = path[2]
                switch (method, path[3], path.count) {
                case ("GET", "directories", 4): return HTTPResourceResponse.json(try encode(await launcher.directories(workspaceID: workspace, access: access)))
                case ("GET", "directories", 5): return HTTPResourceResponse.json(try encode(await launcher.listing(workspaceID: workspace, rootID: path[4], path: query["path"] ?? "", access: access)))
                case ("POST", "sessions", 4):
                    let request = try JSONDecoder().decode(StartSessionRequest.self, from: body)
                    return HTTPResourceResponse.json(try encode(await launcher.start(workspaceID: workspace, request: request, access: access)))
                default: throw BridgeError("not_found", "This resource is not available.", status: 404)
                }
            }
            if method == "GET", path == ["v1", "status"] {
                if let client, let authority {
                    let approved = try await authority.require(client.id, capability: .workspaceRead)
                    data = try encode(JSONValue.object(["protocol": .string("cmux-remote/2"), "host_id": .string(authority.host.id), "capabilities": .array(approved.scope.capabilities.map { .string($0.rawValue) })]))
                } else { data = try encode(await service.status()) }
            } else if method == "GET", path.count == 3, path[0...1] == ["v1", "operations"] {
                guard let id = UUID(uuidString: path[2]) else { throw BridgeError("invalid_input", "An operation identity is required.") }
                data = try encode(await service.operationStatus(id: id, access: access))
            } else if method == "GET", path == ["v1", "workspaces"] {
                try await require(client, .workspaceRead)
                var workspaces = try await service.workspaces()
                if let client, let authority {
                    let current = try await authority.require(client.id, capability: .workspaceRead)
                    workspaces = .object(["workspaces": .array((workspaces["workspaces"].array ?? []).filter { allowed($0["id"].string, current) })])
                }
                data = try encode(workspaces)
            } else if method == "GET", path == ["v1", "sessions"] {
                try await require(client, .conversationRead)
                let sessions = try await service.sessions()
                if let client, let authority { let current = try await authority.require(client.id, capability: .conversationRead); data = try encode(sessions.filter { allowed($0.workspaceID, current) }) }
                else { data = try encode(sessions) }
            } else if method == "GET", path == ["v1", "feed"] {
                try await require(client, .feedRead)
                var feed = try await service.feed()
                if let client, let authority {
                    let current = try await authority.require(client.id, capability: .feedRead)
                    feed = .object(["items": .array((feed["items"].array ?? []).filter { allowed($0["workspace_id"].string, current) })])
                }
                data = try encode(feed)
            } else if path.count == 4, path[0...1] == ["v1", "sessions"] {
                let id = path[2]
                let capability: ClientCapability = method == "POST" ? .conversationControl : (["changes", "diff", "file"].contains(path[3]) ? .projectRead : .conversationRead)
                if method == "POST" {
                    try await require(client, capability)
                } else if let client {
                    let sessions = try await service.sessions()
                    guard let session = sessions.first(where: { $0.id == id }), let workspace = session.workspaceID else { throw BridgeError("scope_denied", "This session is outside this device's approved workspaces.", status: 403) }
                    try await require(client, capability, workspace: workspace)
                }
                switch (method, path[3]) {
                case ("GET", "history"): data = try encode(await service.history(id: id, beforeSeq: query["before_seq"].flatMap(Int.init), limit: query["limit"].flatMap(Int.init) ?? 100, discovered: client != nil, access: access))
                case ("GET", "tool-detail"):
                    guard let messageID = query["message_id"], let generation = query["generation"], let field = query["field"] else { throw BridgeError("invalid_input", "A tool record, generation and field are required.") }
                    if let offset = query["offset"], Int(offset) == nil { throw BridgeError("invalid_input", "The text offset is invalid.") }
                    if let limit = query["limit"], Int(limit) == nil { throw BridgeError("invalid_input", "The text page size is invalid.") }
                    data = try encode(await service.toolText(id: id, messageID: messageID, generation: generation, field: field,
                                                            offset: query["offset"].flatMap(Int.init) ?? 0, contentID: query["content_id"], limit: query["limit"].flatMap(Int.init) ?? 16_384, access: access))
                case ("GET", "image"):
                    guard let reference = query["reference_id"], let generation = query["generation"], reference.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else { throw BridgeError("invalid_input", "A recorded image reference and generation are required.") }
                    data = try await service.image(id: id, referenceID: reference, generation: generation, access: access); image = true
                // The scope check above just ran discovery; the service resolves this id from it rather than again.
                case ("GET", "preview"): data = try encode(await service.preview(id: id, discovered: client != nil, access: access))
                case ("GET", "changes"): data = try encode(await service.changes(id: id, access: access))
                case ("GET", "diff"): data = try encode(await service.diff(id: id, path: query["path"], access: access))
                case ("GET", "file"):
                    guard let relative = query["path"] else { throw BridgeError("invalid_input", "A relative file path is required.") }
                    data = try encode(await service.file(id: id, path: relative, access: access))
                case ("POST", "send"): data = try encode(await service.send(id: id, request: JSONDecoder().decode(SendRequest.self, from: body), access: access))
                case ("POST", "interrupt"): data = try encode(await service.interrupt(id: id, request: JSONDecoder().decode(InterruptRequest.self, from: body), access: access))
                case ("GET", "models"): data = try encode(await service.models(id: id, access: access))
                case ("POST", "model"): data = try encode(await service.switchModel(id: id, request: JSONDecoder().decode(ModelSwitchRequest.self, from: body), access: access))
                // Reopening a conversation starts an Agent in its workspace, so it is a start-class action, not control.
                case ("POST", "resume"):
                    try await require(client, .conversationStart)
                    data = try encode(await service.resume(id: id, request: JSONDecoder().decode(ResumeRequest.self, from: body), access: access))
                default: throw BridgeError("not_found", "This resource is not available.", status: 404)
                }
            } else if method == "POST", path.count == 4, path[0...1] == ["v1", "feed"], path[3] == "reply" {
                // Stored receipts authorize their original scope inside the service;
                // fresh decisions still require a currently pending, scoped target.
                try await require(client, .feedReply)
                data = try encode(await service.reply(requestID: path[2], body: JSONDecoder().decode(JSONValue.self, from: body), access: access))
            } else { throw BridgeError("not_found", "This resource is not available.", status: 404) }
            return HTTPResourceResponse(status: 200, data: data, contentType: image ? "image/jpeg" : "application/json; charset=utf-8")
        } catch {
            let failure = (error as? BridgeError) ?? BridgeError("invalid_request", "The request could not be processed.")
            return HTTPResourceResponse(status: failure.status, data: (try? encode(["error": failure])) ?? Data(), contentType: "application/json; charset=utf-8")
        }
    }
    private func allowed(_ workspace: String?, _ client: EnrolledClient) -> Bool { workspace.map { client.scope.workspaces.contains($0.lowercased()) } ?? false }
    private func require(_ client: EnrolledClient?, _ capability: ClientCapability, workspace: String? = nil) async throws {
        if let client, let authority { _ = try await authority.require(client.id, capability: capability, workspace: workspace) }
    }
    /// Sorted keys make equal answers byte-equal: subscriptions compare bytes, and two equal dictionaries
    /// (the feed's daemon objects) otherwise encode their keys in different orders.
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.sortedKeys]; return try encoder.encode(value)
    }
    private func constantTimeEqual(_ a: String, _ b: String) -> Bool {
        let left = Array(a.utf8); let right = Array(b.utf8); var difference = left.count ^ right.count
        for index in 0..<max(left.count, right.count) { difference |= Int((index < left.count ? left[index] : 0) ^ (index < right.count ? right[index] : 0)) }; return difference == 0
    }
}

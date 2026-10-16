import Foundation
import Observation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Both menu and settings use these exact owner-channel sharing and approval actions.
@MainActor @Observable public final class MacSharingModel {
    public private(set) var status: JSONValue = .null
    public private(set) var workspaces: [JSONValue] = []
    public private(set) var pending: [EnrollmentRequest] = []
    public private(set) var clients: [JSONValue] = []
    public private(set) var qrLink: String?
    public private(set) var expiresAt: Int?
    public private(set) var busy = false
    public private(set) var errorCode: String?
    public var selectedWorkspaces: Set<String> = []
    /// Shared project folders offered to every workspace's new-session list on the phone.
    public private(set) var allowedDirectories: [String] = []
    public var port = 7740
    public var relayOrigin = ""
    public var relayKeyFile = ""
    private var relayDraftLoaded = false
    public var isSharing: Bool { status["state"].string == "running" }
    public var address: String? { status["address"].string }
    private let owner: any CmuxControlling
    private var observation: Task<Void, Never>?
    private var actionError: String?
    public init(owner: any CmuxControlling) { self.owner = owner }
    public func start() {
        guard observation == nil else { return }
        observation = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refresh()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
    }
    public func stopObservation() { observation?.cancel(); observation = nil }
    public func refresh() async {
        guard !busy else { return }
        do {
            status = try await owner.request("bridge.status", params: [:])
            if !relayDraftLoaded {
                relayOrigin = status["relay"]["origin"].string ?? ""; relayKeyFile = status["relay"]["key_file"].string ?? ""; relayDraftLoaded = true
            }
            if let bound = status["port"].int, isSharing { port = bound }
            let requests = try await owner.request("enrollment.pending", params: [:])
            pending = try JSONDecoder().decode([EnrollmentRequest].self, from: JSONEncoder().encode(requests))
            clients = try await owner.request("clients.list", params: [:]).array?.filter { $0["revoked"].bool != true } ?? []
            workspaces = try await owner.request("bridge.workspaces", params: [:])["workspaces"].array ?? []
            // A resident Bridge that predates shared folders answers `sharing_unsupported`; that leaves the
            // list empty instead of failing the whole refresh.
            if let shared = try? await owner.request("directories.allowed", params: [:])["directories"].array { allowedDirectories = shared.compactMap(\.string) }
            selectedWorkspaces.formIntersection(Set(workspaces.compactMap { $0["id"].string?.lowercased() }))
            if let expiresAt, expiresAt <= Int(Date().timeIntervalSince1970) { qrLink = nil; self.expiresAt = nil }
            errorCode = actionError ?? status["error_code"].string
        } catch { errorCode = (error as? BridgeError)?.code ?? "connection_failed" }
    }
    public func setSharing(_ enabled: Bool) async {
        await action {
            status = try await owner.request(enabled ? "bridge.start" : "bridge.stop", params: enabled ? ["port": .number(Double(port))] : [:])
            if !enabled { qrLink = nil; expiresAt = nil }
        }
    }
    public func saveRelay() async {
        await action {
            status = try await owner.request("relay.configure", params: ["origin": .string(relayOrigin.trimmingCharacters(in: .whitespacesAndNewlines)), "key_file": .string(relayKeyFile)])
            relayDraftLoaded = false
        }
    }
    public func removeRelay() async {
        await action { status = try await owner.request("relay.configure", params: [:]); relayDraftLoaded = false }
    }
    public func openPairing() async {
        guard isSharing, !selectedWorkspaces.isEmpty, let address else { errorCode = "pairing_selection"; return }
        await action {
            let result = try await owner.request("enrollment.open", params: ["host": .string(address), "port": .number(Double(port)), "seconds": .number(300), "workspaces": .array(selectedWorkspaces.sorted().map(JSONValue.string))])
            let bootstrap = try JSONDecoder().decode(SignedValue<EnrollmentBootstrap>.self, from: JSONEncoder().encode(result))
            qrLink = try EnrollmentLinkCodec().encode(bootstrap); expiresAt = bootstrap.value.expiresAt
        }
    }
    public func closePairing() async {
        await action { _ = try await owner.request("enrollment.close", params: [:]); qrLink = nil; expiresAt = nil }
    }
    /// The owner may narrow the requested workspaces and withhold starting sessions; approval never expands a request.
    public func approve(_ request: EnrollmentRequest, workspaces: [String]? = nil, allowStart: Bool = true) async {
        await action {
            let chosen = workspaces.map { Set($0.map { $0.lowercased() }) } ?? Set(request.scope.workspaces)
            guard !chosen.isEmpty, chosen.isSubset(of: Set(request.scope.workspaces)) else { throw BridgeError("invalid_scope", "Choose at least one requested workspace.") }
            let capabilities = request.scope.capabilities.filter { allowStart || $0 != .conversationStart }
            let narrowed = ClientScope(workspaces: request.scope.workspaces.filter(chosen.contains), capabilities: capabilities)
            let scope = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(narrowed))
            _ = try await owner.request("enrollment.approve", params: ["request_id": .string(request.requestID), "scope": scope])
        }
    }
    public func deny(_ request: EnrollmentRequest) async {
        await action { _ = try await owner.request("enrollment.deny", params: ["request_id": .string(request.requestID)]) }
    }
    public func revoke(clientID: String) async {
        await action { _ = try await owner.request("clients.revoke", params: ["client_id": .string(clientID)]) }
    }
    /// Replaces the shared folder list; the display form the Bridge returns (`~` for home) is sent back as-is.
    public func saveAllowedDirectories(_ folders: [String]) async {
        await action { _ = try await owner.request("directories.set_allowed", params: ["directories": .array(folders.map(JSONValue.string))]) }
    }
    private func action(_ operation: () async throws -> Void) async {
        guard !busy else { return }; busy = true
        do { try await operation(); actionError = nil; errorCode = nil }
        catch { actionError = (error as? BridgeError)?.code ?? "connection_failed"; errorCode = actionError; busy = false; return }
        busy = false; await refresh()
    }
}

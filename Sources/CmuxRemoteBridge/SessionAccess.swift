import CmuxRemoteCore

/// Per-request policy is rechecked inside the service after its final target refresh.
public struct SessionAccess: Sendable {
    let clientID: String
    var principalID: String { clientID }
    private let check: @Sendable (ClientCapability, String) async throws -> Void
    private let checkAll: (@Sendable ([ClientCapability], String) async throws -> Void)?
    public init(clientID: String = "owner", principalID: String? = nil, checkAll: (@Sendable ([ClientCapability], String) async throws -> Void)? = nil, check: @escaping @Sendable (ClientCapability, String) async throws -> Void) { self.clientID = principalID ?? clientID; self.checkAll = checkAll; self.check = check }
    func require(_ capability: ClientCapability, workspace: String?) async throws {
        guard let workspace else { throw BridgeError("scope_denied", "This resource has no approved workspace binding.", status: 403) }
        try await check(capability, workspace)
    }
    /// Production access checks all required capabilities in one authority actor turn.
    func require(_ capabilities: [ClientCapability], workspace: String?) async throws {
        guard let workspace else { throw BridgeError("scope_denied", "This resource has no approved workspace binding.", status: 403) }
        if let checkAll { try await checkAll(capabilities, workspace) }
        else { for capability in capabilities { try await check(capability, workspace) } }
    }
}

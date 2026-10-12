import CmuxRemoteCore

/// Per-request policy is rechecked inside the service after its final target refresh.
public struct SessionAccess: Sendable {
    let principalID: String
    private let check: @Sendable (ClientCapability, String) async throws -> Void
    public init(principalID: String = "legacy", check: @escaping @Sendable (ClientCapability, String) async throws -> Void) { self.principalID = principalID; self.check = check }
    func require(_ capability: ClientCapability, workspace: String?) async throws {
        guard let workspace else { throw BridgeError("scope_denied", "This resource has no approved workspace binding.", status: 403) }
        try await check(capability, workspace)
    }
}

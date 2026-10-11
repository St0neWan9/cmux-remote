import Foundation

/// Approval is confined to these explicit workspace UUIDs.
public struct ClientScope: Codable, Sendable, Equatable {
    public var workspaces: [String]
    public var capabilities: [ClientCapability]
    public init(workspaces: [String], capabilities: [ClientCapability]) {
        self.workspaces = workspaces.map { $0.lowercased() }.sorted(); self.capabilities = capabilities.sorted { $0.rawValue < $1.rawValue }
    }
    public func validate() throws {
        guard !workspaces.isEmpty, workspaces.count <= 100, workspaces.allSatisfy({ UUID(uuidString: $0) != nil }),
              Set(workspaces).count == workspaces.count, !capabilities.isEmpty, Set(capabilities).count == capabilities.count else {
            throw BridgeError("invalid_scope", "Choose explicit workspaces and supported permissions.")
        }
    }
}

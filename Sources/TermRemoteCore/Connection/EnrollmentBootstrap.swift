import Foundation

/// Host-signed bootstrap for one short-lived enrollment window; contains no permanent credential.
public struct EnrollmentBootstrap: Codable, Sendable, Equatable {
    public var version: Int = 2
    public var host: HostIdentity
    public var endpoint: BridgeEndpoint
    public var workspaces: [String]
    public var windowID: String
    public var expiresAt: Int
    public init(host: HostIdentity, endpoint: BridgeEndpoint, workspaces: [String], windowID: String, expiresAt: Int) {
        self.host = host; self.endpoint = endpoint; self.workspaces = workspaces; self.windowID = windowID; self.expiresAt = expiresAt
    }
}

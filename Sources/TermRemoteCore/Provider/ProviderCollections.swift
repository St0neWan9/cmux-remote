import Foundation

/// A provider-neutral listing. One provider's failure is reported without
/// hiding another provider's resources.
public struct SpaceList: Codable, Sendable, Equatable {
    public let spaces: [SpaceDescriptor]
    public let providerErrors: [String]
    public init(spaces: [SpaceDescriptor], providerErrors: [String] = []) {
        self.spaces = spaces; self.providerErrors = providerErrors
    }
    enum CodingKeys: String, CodingKey { case spaces; case providerErrors = "provider_errors" }
}

public struct TerminalList: Codable, Sendable, Equatable {
    public let terminals: [TerminalDescriptor]
    public init(terminals: [TerminalDescriptor]) { self.terminals = terminals }
}

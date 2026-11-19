import Foundation

/// One provider instance as a device may see it. Identifiers are UUIDs; raw
/// provider ids and endpoints are never part of this resource.
public struct ProviderDescriptor: Codable, Sendable, Identifiable, Equatable {
    public let id: String
    public let kind: ProviderKind
    public let name: String
    public let hostID: String?
    public let hostName: String
    public let apiRevision: String?
    public let capabilities: [ProviderCapability]
    public let status: ProviderStatus
    public let errorCode: String?

    public init(id: String, kind: ProviderKind, name: String, hostID: String? = nil, hostName: String,
                apiRevision: String? = nil, capabilities: [ProviderCapability], status: ProviderStatus = .available,
                errorCode: String? = nil) {
        self.id = id; self.kind = kind; self.name = name; self.hostID = hostID; self.hostName = hostName
        self.apiRevision = apiRevision
        self.capabilities = Array(Set(capabilities)).sorted { $0.rawValue < $1.rawValue }
        self.status = status; self.errorCode = errorCode
    }
}

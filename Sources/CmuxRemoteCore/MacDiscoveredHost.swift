import Foundation

/// Public Bonjour hints returned over the private local owner channel; these confer no authority.
public struct MacDiscoveredHost: Codable, Sendable {
    public let host: HostIdentity
    public let serviceName: String
    public let serviceType: String
    public let serviceDomain: String
    public init(host: HostIdentity, serviceName: String, serviceType: String, serviceDomain: String) {
        self.host = host; self.serviceName = serviceName; self.serviceType = serviceType; self.serviceDomain = serviceDomain
    }
}

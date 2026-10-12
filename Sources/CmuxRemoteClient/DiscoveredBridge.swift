import Foundation
import Network
import CmuxRemoteCore

/// Bonjour supplies only an untrusted identity/reachability hint until explicit first-use trust.
public struct DiscoveredBridge: Sendable, Identifiable {
    public let host: HostIdentity
    public let service: NWEndpoint
    public var id: String { host.id + ":" + service.debugDescription }
    public init(host: HostIdentity, service: NWEndpoint) { self.host = host; self.service = service }
}

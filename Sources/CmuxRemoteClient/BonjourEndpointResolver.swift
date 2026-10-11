import Foundation
import Network
import CmuxRemoteCore

/// Converts Network.framework endpoints to URL hosts without debug-only interface suffixes.
struct BonjourEndpointResolver: Sendable {
    func resolve(_ endpoint: NWEndpoint?) throws -> BridgeEndpoint {
        guard case .hostPort(let host, let port) = endpoint else { throw BridgeError("discovery_failed", "The service endpoint could not be resolved.") }
        let name: String
        switch host {
        case .name(let value, _): name = value
        case .ipv4(let address): name = address.rawValue.map { String($0) }.joined(separator: ".")
        case .ipv6(let address): name = "[" + address.debugDescription + "]"
        @unknown default: throw BridgeError("discovery_failed", "Unsupported service address.")
        }
        let value = BridgeEndpoint(host: name, port: Int(port.rawValue)); try value.validate(); return value
    }
}

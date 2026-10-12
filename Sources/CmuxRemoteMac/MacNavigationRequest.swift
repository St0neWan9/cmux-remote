import Foundation
import CmuxRemoteCore

/// Non-secret containing-app navigation; URLs never contain credentials or shell commands.
public struct MacNavigationRequest: Sendable {
    public let hostID: String?
    public init(url: URL) throws {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false), components.scheme == "cmux-remote-mac",
              components.host == "devices", components.path.isEmpty, components.user == nil, components.fragment == nil else {
            throw BridgeError("invalid_input", "Unsupported Companion navigation URL.")
        }
        let items = components.queryItems ?? []
        guard items.count <= 1, items.allSatisfy({ $0.name == "host" }) else { throw BridgeError("invalid_input", "Unsupported navigation parameters.") }
        let id = items.first?.value
        guard id == nil || (id!.count == 64 && id!.allSatisfy({ $0.isASCII && $0.isHexDigit })) else { throw BridgeError("invalid_identity", "Invalid host identity.") }
        hostID = id
    }
    public static func url(hostID: String? = nil) -> URL {
        var value = URLComponents(); value.scheme = "cmux-remote-mac"; value.host = "devices"
        if let hostID { value.queryItems = [URLQueryItem(name: "host", value: hostID)] }
        return value.url!
    }
}

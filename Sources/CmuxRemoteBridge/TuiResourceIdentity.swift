import Foundation
import CryptoKit
import CmuxRemoteCore

/// Namespaces typed daemon resources into the existing UUID-based approval contract.
public struct TuiResourceIdentity: Sendable {
    public init() {}
    public func validate(_ id: String?, prefix: String) throws -> String {
        guard let id, id.hasPrefix(prefix + "_"), id.count == prefix.count + 33,
              id.dropFirst(prefix.count + 1).allSatisfy({ "0123456789abcdef".contains($0) }) else {
            throw BridgeError("invalid_response", "The daemon resource identity is invalid.", status: 502)
        }
        return id
    }
    public func uuid(machine: String, session: String, resource: String) -> String {
        let bytes = Array(SHA256.hash(data: Data(("cmux-remote/tui/v1\u{0}" + machine + "\u{0}" + session + "\u{0}" + resource).utf8)).prefix(16))
        return UUID(uuid: (bytes[0],bytes[1],bytes[2],bytes[3],bytes[4],bytes[5],bytes[6],bytes[7],bytes[8],bytes[9],bytes[10],bytes[11],bytes[12],bytes[13],bytes[14],bytes[15])).uuidString.lowercased()
    }
    public func conversation(machine: String, session: String, terminal: String, provider: String, providerSession: String) -> String {
        "tui:" + uuid(machine: machine, session: session, resource: terminal + ":" + provider + ":" + providerSession.lowercased())
    }
}

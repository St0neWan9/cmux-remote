import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Fixed local client operations shared with the resident Companion authority.
public struct MacClientConnector: Sendable {
    private let owner: any CmuxControlling
    /// Creates a connector with an injected private owner-channel client.
    public init(owner: any CmuxControlling) { self.owner = owner }
    /// Returns saved hosts and enrollment state without initiating a connection.
    public func status() async throws -> JSONValue {
        let enrollment: JSONValue
        do { enrollment = try await owner.request("mac.enrollment.status", params: [:]) }
        catch let error as BridgeError where error.code == "enrollment_pending" {
            enrollment = .object(["state": .string("idle")])
        }
        // An approval poll persists its grant; read saved hosts afterwards.
        let connections = try await owner.request("mac.connections", params: [:])
        guard connections.array != nil else { throw BridgeError("invalid_response", "Invalid saved connections.") }
        return .object(["connections": connections, "enrollment": enrollment])
    }
    /// Returns current public discovery hints without approving a peer.
    public func discover() async throws -> [MacDiscoveredHost] {
        try decode([MacDiscoveredHost].self, await owner.request("mac.discovery.list", params: [:]))
    }
    /// Restores saved trust or requests enrollment after exact first-use certificate confirmation.
    public func connect(hostID: String, confirmedCertificate: String?, clientName: String) async throws -> JSONValue {
        guard hostID.count == 64, hostID.allSatisfy({ $0.isASCII && $0.isHexDigit }) else { throw BridgeError("invalid_input", "Choose an exact discovered host identity.") }
        let saved = try await owner.request("mac.connections", params: [:]).array?.first { $0["id"].string == hostID }
        let discovered = try await discover().first { $0.host.id == hostID }
        let host: HostIdentity, endpoint: BridgeEndpoint
        if let discovered {
            host = discovered.host
            try IdentityCryptography().validate(host)
            if saved == nil {
                guard confirmedCertificate?.lowercased() == host.certificateSHA256.lowercased() else {
                    throw BridgeError("trust_required", "Verify the host fingerprint, then pass --trust-certificate SHA256.")
                }
            }
            endpoint = try decode(BridgeEndpoint.self, await owner.request("mac.discovery.resolve", params: ["host_id": .string(hostID)]))
        } else if let saved {
            host = try decode(HostIdentity.self, saved["host"]); endpoint = try decode(BridgeEndpoint.self, saved["endpoint"])
        } else { throw BridgeError("not_connected", "Choose a currently discovered host or a saved connection.") }
        try IdentityCryptography().validate(host); try endpoint.validate()
        return try await owner.request("mac.enrollment.start", params: ["host": try json(host), "endpoint": try json(endpoint),
            "trust_confirmed": .bool(true), "name": .string(clientName)])
    }
    private func decode<T: Decodable>(_ type: T.Type, _ value: JSONValue) throws -> T { try JSONDecoder().decode(type, from: JSONEncoder().encode(value)) }
    private func json<T: Encodable>(_ value: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) }
}

import Foundation
import CmuxRemoteCore

/// Owner-only outgoing device identity and host grants, shared by resident CLI services.
public actor MacConnectionRepository {
    private let directory: URL
    public init(directory: URL) { self.directory = directory }
    public func privateKey() throws -> Data {
        try prepare()
        let path = directory.appendingPathComponent("mac-device-key")
        if FileManager.default.fileExists(atPath: path.path) { return try Data(contentsOf: path) }
        let key = IdentityCryptography().generatePrivateKey(); try write(key, to: path); return key
    }
    public func connections() throws -> [AuthorizedConnection] {
        let path = directory.appendingPathComponent("mac-connections.json")
        guard FileManager.default.fileExists(atPath: path.path) else { return [] }
        let bytes = try Data(contentsOf: path)
        guard bytes.count <= 1_048_576 else { throw BridgeError("invalid_state", "Saved connection state is too large.") }
        let connections = try JSONDecoder().decode([AuthorizedConnection].self, from: bytes)
        try connections.forEach { try $0.validate() }; return connections
    }
    public func save(_ connection: AuthorizedConnection) throws {
        try connection.validate(); try prepare()
        var values = try connections().filter { $0.host.id != connection.host.id }
        guard values.count < 64 else { throw BridgeError("connection_capacity", "Remove a saved host before adding another.") }
        values.append(connection); try write(JSONEncoder().encode(values), to: directory.appendingPathComponent("mac-connections.json"))
    }
    public func connection(hostID: String) throws -> AuthorizedConnection {
        guard let value = try connections().first(where: { $0.host.id == hostID }) else { throw BridgeError("not_connected", "Enroll this Mac with the selected host first.") }
        return value
    }
    public func remove(hostID: String) throws {
        try prepare(); try write(JSONEncoder().encode(connections().filter { $0.host.id != hostID }), to: directory.appendingPathComponent("mac-connections.json"))
    }
    private func prepare() throws { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]) }
    private func write(_ bytes: Data, to path: URL) throws {
        try bytes.write(to: path, options: .atomic); try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
    }
}

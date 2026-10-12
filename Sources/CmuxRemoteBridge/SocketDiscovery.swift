import Foundation
import CmuxRemoteCore

/// Discovers official socket locations without modifying cmux configuration.
public struct SocketDiscovery: Sendable {
    public init() {}
    public func resolve(explicit: String?, environment: [String: String], home: URL) throws -> String {
        if let path = explicit ?? environment["CMUX_SOCKET_PATH"], !path.isEmpty { return path }
        let state = home.appendingPathComponent(".local/state/cmux")
        if let marker = try? String(contentsOf: state.appendingPathComponent("last-socket-path"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), !marker.isEmpty { return marker }
        let candidates = [state.appendingPathComponent("cmux.sock").path, home.appendingPathComponent(".config/cmux/cmux.sock").path, "/tmp/cmux.sock"]
        guard let path = candidates.first(where: { FileManager.default.fileExists(atPath: $0) }) else { throw BridgeError("socket_unavailable", "No cmux socket was found. Open cmux or pass --socket.", status: 503) }
        return path
    }
}

import TermRemoteCore

/// The local controller used when no cmux desktop or cmux-tui daemon is running.
///
/// A Term Remote Bridge still serves provider sources such as Rex in that case. The cmux
/// inventory answers empty so the generic routes stay usable; anything that would have to
/// drive cmux is reported as unsupported instead of pretending success.
public struct NoCmuxBackend: CmuxControlling {
    public init() {}
    public func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "system.ping":
            return .object(["active_backends": .number(0)])
        case "system.capabilities":
            return .object([:])
        case "workspace.list":
            return .object(["workspaces": .array([])])
        case "vault.sessions", "chat.sessions.dump":
            return .object(["sessions": .array([])])
        case "feed.list":
            return .object(["items": .array([])])
        default:
            throw BridgeError("unsupported", "This operation needs a cmux backend.", status: 422)
        }
    }
}

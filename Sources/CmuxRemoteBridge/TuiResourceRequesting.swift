import CmuxRemoteCore

/// Fixed resource requests against one explicitly selected local daemon.
public protocol TuiResourceRequesting: Sendable {
    func resource(_ operation: String, params: [String: JSONValue], idempotencyKey: String?) async throws -> JSONValue
    /// A bounded, non-following stream read: at most `limit` items, then the position to continue from.
    func stream(_ operation: String, params: [String: JSONValue], limit: Int) async throws -> TuiStreamRead
}

extension TuiResourceRequesting {
    public func stream(_ operation: String, params: [String: JSONValue], limit: Int) async throws -> TuiStreamRead {
        throw BridgeError("unsupported", "This daemon client cannot read streams.", status: 422)
    }
}

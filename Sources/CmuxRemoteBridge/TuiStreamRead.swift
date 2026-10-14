import CmuxRemoteCore

/// Items of one bounded daemon stream read and the cursor after the last item delivered.
public struct TuiStreamRead: Sendable {
    public let items: [JSONValue]
    public let cursor: JSONValue
    /// False when the read stopped at its item limit before the daemon ended the stream.
    public let complete: Bool
    public init(items: [JSONValue], cursor: JSONValue, complete: Bool) { self.items = items; self.cursor = cursor; self.complete = complete }
}

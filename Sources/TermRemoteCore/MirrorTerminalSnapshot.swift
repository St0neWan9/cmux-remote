import Foundation

/// An authoritative replay for one producer lifetime, already encoded to VT bytes.
public struct MirrorTerminalSnapshot: Codable, Sendable {
    public let workspaceID: String
    public let surfaceID: String
    public let runtimeEpoch: String
    public let columns: Int
    public let rows: Int
    public let bytes: Data
    /// Stable geometry, screen, mode and theme identity for positioned repaints.
    public var presentationKey: String?
    /// An optional repaint that keeps the established terminal screen intact.
    public var repaintBytes: Data?
    /// Optional validated cells for fitting a desktop viewer without resizing the producer.
    public var renderGrid: JSONValue?
    /// Peers without this flag must not receive bracketed-paste payloads.
    public var pasteSupported: Bool?
    public var allowsInput = false
    public init(workspaceID: String, surfaceID: String, runtimeEpoch: String, columns: Int, rows: Int, bytes: Data) {
        self.workspaceID = workspaceID; self.surfaceID = surfaceID; self.runtimeEpoch = runtimeEpoch
        self.columns = columns; self.rows = rows; self.bytes = bytes
    }
}

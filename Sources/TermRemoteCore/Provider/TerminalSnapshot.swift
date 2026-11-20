import Foundation

/// A bounded terminal screen. `revision` is opaque: equal revisions describe
/// the same provider state, and a different one means the view changed.
public struct TerminalSnapshot: Codable, Sendable, Equatable {
    public let providerID: String
    public let spaceID: String
    public let terminalID: String
    public let revision: String
    public let columns: Int
    public let rows: Int
    /// "text" for a plain-text screen, "vt" when `vt` carries a replay.
    public let format: String
    public let text: String
    public let vt: Data?
    public let truncated: Bool
    public let capturedAt: Date

    public init(providerID: String, spaceID: String, terminalID: String, revision: String,
                columns: Int, rows: Int, format: String, text: String, vt: Data? = nil,
                truncated: Bool = false, capturedAt: Date = Date()) {
        self.providerID = providerID; self.spaceID = spaceID; self.terminalID = terminalID
        self.revision = revision; self.columns = columns; self.rows = rows
        self.format = format; self.text = text; self.vt = vt; self.truncated = truncated
        self.capturedAt = capturedAt
    }
}

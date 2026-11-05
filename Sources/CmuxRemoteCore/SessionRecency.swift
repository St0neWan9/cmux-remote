import Foundation

/// Which conversations a list shows at once and which it folds under "earlier".
///
/// A Mac keeps every conversation it ever ran, and most of them are history: the list opened on dozens of rows
/// the reader had no reason to see. A conversation stays in view while it is running, waiting on the reader or
/// active within the recent window; the rest fold, but every list keeps at least a few of its newest rows so a
/// group never collapses to a bare heading. The rule is the same on every client.
public struct SessionRecency: Sendable {
    /// How far back activity keeps a conversation in view.
    public static let window: TimeInterval = 3 * 24 * 60 * 60
    /// The newest rows a workspace group keeps in view however old they are.
    public static let workspaceFloor = 3
    /// The newest rows the time-ordered list keeps in view however old they are.
    public static let timeFloor = 6

    public let now: Date
    public init(now: Date = Date()) { self.now = now }

    /// Whether a conversation stays in view on its own merits.
    public func isRecent(_ session: SessionDescriptor) -> Bool {
        if session.state.hasPrefix("working") || session.state == "needs_input" { return true }
        guard let updatedAt = session.updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) < Self.window
    }
    /// Splits rows already in display order into what is shown and what folds.
    ///
    /// The newest `floor` rows are always shown; past them, a row is shown only when it is recent. A recent row
    /// below an older one is still shown, so a running conversation the Bridge reported without a time is never
    /// folded away.
    public func split<Row>(_ rows: [Row], floor: Int, session: (Row) -> SessionDescriptor) -> (shown: [Row], earlier: [Row]) {
        var shown: [Row] = [], earlier: [Row] = []
        for (index, row) in rows.enumerated() {
            if index < floor || isRecent(session(row)) { shown.append(row) } else { earlier.append(row) }
        }
        return (shown, earlier)
    }
}

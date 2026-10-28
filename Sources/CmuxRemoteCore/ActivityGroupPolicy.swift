import Foundation

/// How an activity group is drawn inside the timeline.
///
/// A running Agent adds an operation every few seconds. Drawn whole, the group becomes one enormous row that
/// SwiftUI lays out in full on every refresh — the cause of both the stutter and the long blank after collapsing.
/// So a group over the limit stays open while it runs but draws only its newest slice; the count in its header
/// still tracks the whole turn, and the full page is one tap away.
public enum ActivityGroupPolicy {
    /// Operations a group may draw whole.
    public static let inlineLimit = 5
    /// Messages of the newest slice drawn while a longer group is open.
    public static let windowMessages = 10
    /// A group is open while it is the newest, unless the reader said otherwise.
    public static func isExpanded(isLatest: Bool, choice: Bool?) -> Bool { choice ?? isLatest }
    /// Whether the group draws every message it has, or only its newest slice.
    public static func drawsWhole(operationCount: Int) -> Bool { operationCount <= inlineLimit }
}

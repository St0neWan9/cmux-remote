import SwiftUI

/// Asks the timeline to keep a row on screen while its own disclosure changes height.
///
/// A tool card that grows or shrinks changes the height of the row it sits in, and the timeline's
/// follower reacts to that the same way it reacts to a new message: it scrolls to the newest row, which
/// throws the reader away from the card they just opened. A toggle therefore pauses following and, once
/// the new height is laid out, restores the row's place.
struct TimelineRowAnchor: Equatable {
    var messageID: String?
    var token = 0
    /// The request the rows read; the timeline replaces it on every toggle.
    func request(_ messageID: String?) -> TimelineRowAnchor { TimelineRowAnchor(messageID: messageID, token: token + 1) }
}

private struct TimelineRowAnchorKey: EnvironmentKey {
    /// Only ever set and called from the main actor by SwiftUI views, and never stored beyond the view tree.
    nonisolated(unsafe) static let defaultValue: (String?) -> Void = { _ in }
}

extension EnvironmentValues {
    /// Called by a row whose height is about to change; the identifier is the row it belongs to.
    var keepRowVisible: (String?) -> Void {
        get { self[TimelineRowAnchorKey.self] }
        set { self[TimelineRowAnchorKey.self] = newValue }
    }
}

/// The measured top of the row whose disclosure is changing, in the timeline's coordinates.
struct AdjustingRowTopPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { if let next = nextValue() { value = next } }
}

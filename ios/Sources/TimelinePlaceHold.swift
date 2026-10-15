import SwiftUI

/// Lets a row tell the timeline that the reader is looking at it, so the page stays where it is.
///
/// The timeline follows new content while the newest message is on screen. A tool card opened there would
/// otherwise be carried off by the next message to arrive, at a moment nobody can predict. Opening or closing
/// one therefore stops following until the reader scrolls or asks for the latest message again.
private struct TimelinePlaceHoldKey: EnvironmentKey {
    /// Only ever set and called from the main actor by SwiftUI views, and never stored beyond the view tree.
    nonisolated(unsafe) static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    /// Called by a row just before its height changes because the reader opened or closed something in it.
    var holdPlace: () -> Void {
        get { self[TimelinePlaceHoldKey.self] }
        set { self[TimelinePlaceHoldKey.self] = newValue }
    }
}

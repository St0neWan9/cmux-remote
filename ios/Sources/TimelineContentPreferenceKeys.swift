import SwiftUI

/// The content's own height, measured before the page's blank tail: the tail is sized from it, so it must
/// not depend on the tail itself.
struct TimelineContentHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { 0 }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

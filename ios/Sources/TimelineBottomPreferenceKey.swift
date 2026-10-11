import SwiftUI

/// Tracks the visible bottom, independently of when SwiftUI creates a row.
struct TimelineBottomPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat { .infinity }
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

import SwiftUI

/// The edge-swipe decision for a page that replaces the root instead of being pushed.
///
/// The drawer's "Add Mac" swaps the whole root view, so there is no navigation stack entry to pop and
/// UIKit's own interactive-pop recognizer never applies. The same drag is judged here instead.
struct EdgeBackSwipe: Equatable {
    /// How far from the leading edge a drag may start, the width UIKit itself reserves.
    let edge: CGFloat
    /// How far the drag must travel before it counts as a back.
    let commit: CGFloat
    /// The threshold below which a drag is treated as a touch, not a gesture.
    let threshold: CGFloat
    init(edge: CGFloat = 24, commit: CGFloat = 56, threshold: CGFloat = 12) { self.edge = edge; self.commit = commit; self.threshold = threshold }
    /// Whether a drag may begin: only from the leading strip.
    func begins(at location: CGPoint) -> Bool { location.x >= 0 && location.x <= edge }
    /// Whether the drag is a horizontal, forward one rather than a vertical scroll or a wiggle.
    func tracks(_ translation: CGSize) -> Bool { translation.width > 0 && abs(translation.width) > abs(translation.height) }
    /// Whether releasing now completes the back.
    func commits(_ translation: CGSize) -> Bool { tracks(translation) && translation.width >= commit }
    /// How far the page follows the finger, never left of its resting place.
    func offset(_ translation: CGSize) -> CGFloat { tracks(translation) ? translation.width : 0 }
    /// The gesture itself: a drag from the leading strip that completes a back when released past the
    /// commit distance.
    func gesture(_ back: @escaping () -> Void) -> some Gesture {
        DragGesture(minimumDistance: threshold)
            .onEnded { value in if begins(at: value.startLocation), commits(value.translation) { back() } }
    }
}

/// Applies the edge swipe only when the page carries a custom back action.
struct ConditionalEdgeBackSwipe: ViewModifier {
    let back: (() -> Void)?
    func body(content: Content) -> some View {
        if let back { content.simultaneousGesture(EdgeBackSwipe().gesture(back)) }
        else { content }
    }
}

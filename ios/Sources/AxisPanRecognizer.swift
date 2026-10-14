import SwiftUI
import UIKit

/// A pan along one axis that only begins when it can move the content, so other drags stay with the page.
///
/// A SwiftUI drag inside a scroll view's content takes every drag, even attached simultaneously; a UIKit pan can
/// decline to begin. It declines a drag across its axis, and one that pushes past the content's edge, which
/// hands the page its scroll the way a native nested scroll view does.
@available(iOS 18.0, *)
struct AxisPanRecognizer: UIGestureRecognizerRepresentable {
    let axis: Axis
    /// Whether the content can still move for a drag in this direction (positive: right or down).
    let canMove: (CGFloat) -> Bool
    /// The translation along the axis so far.
    let changed: (CGFloat) -> Void
    /// The final translation and where a flick would carry it.
    let ended: (CGFloat, CGFloat) -> Void
    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator(axis: axis, canMove: canMove) }
    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.delegate = context.coordinator
        return pan
    }
    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) { context.coordinator.canMove = canMove }
    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = along(recognizer.translation(in: recognizer.view))
        switch recognizer.state {
        case .began, .changed: changed(translation)
        case .ended, .cancelled: ended(translation, translation + along(recognizer.velocity(in: recognizer.view)) * 0.25)
        default: break
        }
    }
    private func along(_ point: CGPoint) -> CGFloat { axis == .vertical ? point.y : point.x }
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        let axis: Axis
        var canMove: (CGFloat) -> Bool
        init(axis: Axis, canMove: @escaping (CGFloat) -> Bool) { self.axis = axis; self.canMove = canMove }
        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            let along = axis == .vertical ? velocity.y : velocity.x, across = axis == .vertical ? velocity.x : velocity.y
            return abs(along) > abs(across) && canMove(along)
        }
    }
}

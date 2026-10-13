import SwiftUI

/// Scrolls content inside a fixed length without a UIKit scroll view.
///
/// Conversation rows near the header and composer are drawn through a Metal layer effect, which cannot draw
/// UIKit-backed views: a `ScrollView` there renders as an empty box. Offsetting clipped SwiftUI content can.
struct ClippedScroller<Content: View>: View {
    let axis: Axis
    /// The visible length along `axis`.
    let length: CGFloat
    /// The content's full length along `axis`.
    let contentLength: CGFloat
    @ViewBuilder let content: () -> Content
    @State private var offset: CGFloat = 0
    @State private var dragStart: CGFloat?
    /// Whether the current drag runs along `axis`; decided once it has moved, so a page swipe is left alone.
    @State private var alongAxis: Bool?
    init(_ axis: Axis = .vertical, length: CGFloat, contentLength: CGFloat, @ViewBuilder content: @escaping () -> Content) {
        self.axis = axis; self.length = length; self.contentLength = contentLength; self.content = content
    }
    private var maxOffset: CGFloat { max(0, contentLength - length) }
    var body: some View {
        content()
            .offset(x: axis == .horizontal ? -offset : 0, y: axis == .vertical ? -offset : 0)
            .frame(width: axis == .horizontal ? length : nil, height: axis == .vertical ? length : nil,
                   alignment: axis == .horizontal ? .leading : .top)
            .clipped()
            .contentShape(Rectangle())
            .overlay(alignment: axis == .horizontal ? .bottomLeading : .topTrailing) { indicator }
            .modifier(AxisPan(axis: axis, enabled: maxOffset > 0, drag: drag,
                              // Dragging toward positive moves back toward the start; past an edge, the page scrolls.
                              canMove: { direction in direction > 0 ? offset > 0.5 : offset < maxOffset - 0.5 },
                              changed: { translation in
                                  let start = dragStart ?? offset
                                  dragStart = start
                                  offset = clamp(start - translation)
                              },
                              ended: { _, predicted in
                                  let start = dragStart ?? offset
                                  dragStart = nil
                                  withAnimation(.easeOut(duration: 0.35)) { offset = clamp(start - predicted) }
                              }))
            .onChange(of: contentLength) { _, _ in offset = clamp(offset) }
            .accessibilityScrollAction { edge in
                let forward = edge == .bottom || edge == .trailing
                withAnimation { offset = clamp(offset + (forward ? length * 0.8 : -length * 0.8)) }
            }
    }
    private var drag: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                if alongAxis == nil {
                    let along = abs(distance(value.translation)), across = abs(crossDistance(value.translation))
                    alongAxis = along > across
                }
                guard alongAxis == true else { return }
                let start = dragStart ?? offset
                dragStart = start
                offset = clamp(start - distance(value.translation))
            }
            .onEnded { value in
                defer { alongAxis = nil; dragStart = nil }
                guard alongAxis == true else { return }
                // Carry the flick on, as a native scroll view would.
                let start = dragStart ?? offset
                withAnimation(.easeOut(duration: 0.35)) { offset = clamp(start - distance(value.predictedEndTranslation)) }
            }
    }
    /// A thin bar shows that there is more, and where the visible part sits.
    @ViewBuilder private var indicator: some View {
        if maxOffset > 0 {
            let bar = max(24, length * length / max(contentLength, 1))
            let position = (length - bar) * offset / maxOffset
            if axis == .vertical {
                Capsule().fill(Color.black.opacity(0.18)).frame(width: 3, height: bar).offset(x: 6, y: position).allowsHitTesting(false)
            } else {
                Capsule().fill(Color.black.opacity(0.18)).frame(width: bar, height: 3).offset(x: position, y: 6).allowsHitTesting(false)
            }
        }
    }
    private func distance(_ translation: CGSize) -> CGFloat { axis == .vertical ? translation.height : translation.width }
    private func crossDistance(_ translation: CGSize) -> CGFloat { axis == .vertical ? translation.width : translation.height }
    private func clamp(_ value: CGFloat) -> CGFloat { min(max(0, value), maxOffset) }
}

/// Scrolling that leaves other drags to the page: a UIKit pan where available, a shared drag before.
private struct AxisPan<G: Gesture>: ViewModifier {
    let axis: Axis
    let enabled: Bool
    let drag: G
    let canMove: (CGFloat) -> Bool
    let changed: (CGFloat) -> Void
    let ended: (CGFloat, CGFloat) -> Void
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            if enabled { content.gesture(AxisPanRecognizer(axis: axis, canMove: canMove, changed: changed, ended: ended)) } else { content }
        } else {
            content.simultaneousGesture(drag, isEnabled: enabled)
        }
    }
}

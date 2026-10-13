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
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        let start = dragStart ?? offset
                        dragStart = start
                        offset = clamp(start - distance(value.translation))
                    }
                    .onEnded { value in
                        // Carry the flick on, as a native scroll view would.
                        let start = dragStart ?? offset
                        dragStart = nil
                        withAnimation(.easeOut(duration: 0.35)) { offset = clamp(start - distance(value.predictedEndTranslation)) }
                    },
                // A content that fits needs no gesture, so the page keeps its own scroll and swipe-back.
                isEnabled: maxOffset > 0
            )
            .onChange(of: contentLength) { _, _ in offset = clamp(offset) }
            .accessibilityScrollAction { edge in
                let forward = edge == .bottom || edge == .trailing
                withAnimation { offset = clamp(offset + (forward ? length * 0.8 : -length * 0.8)) }
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
    private func clamp(_ value: CGFloat) -> CGFloat { min(max(0, value), maxOffset) }
}

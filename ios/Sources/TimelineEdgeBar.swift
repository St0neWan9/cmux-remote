import SwiftUI

/// The conversation's header or composer, as a bar the scroll view softens its content under where the system can.
struct TimelineEdgeBar<Bar: View>: ViewModifier {
    let edge: VerticalEdge
    @ViewBuilder let bar: () -> Bar
    func body(content: Content) -> some View {
        if #available(iOS 26, *) { content.safeAreaBar(edge: edge, spacing: 0, content: bar) }
        else { content.safeAreaInset(edge: edge, spacing: 0, content: bar) }
    }
}

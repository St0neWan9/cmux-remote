import SwiftUI

/// The conversation's header or composer: an opaque bar in the safe area that dissolves into the page
/// over its last few points.
///
/// The treatment lives on the bar, never on a row. A per-row layer effect rasterizes the row, which
/// stops the vendored text view from drawing its selection.
///
/// The bar is page-white, not a material. Messages scroll under a bar on this OS, and no material is
/// opaque enough to hide them: the text shows through the header title and behind the composer, and
/// `Reduce Transparency` changes how much. Solid white hides them everywhere, and the short gradient
/// past the bar's inner edge keeps the seam from being a hard line — the same soft white transition the
/// Metal header shader drew before this.
struct TimelineEdgeBar<Bar: View>: ViewModifier {
    let edge: VerticalEdge
    @ViewBuilder let bar: () -> Bar

    /// How far past the bar the rows dissolve. It is drawn beyond the bar's own bounds and costs no
    /// layout, so no message is buried under blank space and no transparent band sits inside the bar.
    private static var fade: CGFloat { 12 }

    private var atTop: Bool { edge == .top }

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectStyle(.soft, for: .vertical).safeAreaBar(edge: edge, spacing: 0) { paintedBar }
        } else {
            content.safeAreaInset(edge: edge, spacing: 0) { paintedBar }
        }
    }

    private var paintedBar: some View {
        bar().background(alignment: atTop ? .bottom : .top) { paint }
    }

    /// Page white across the whole bar, then a gradient bleed onto the rows just past its inner edge.
    private var paint: some View {
        ZStack(alignment: atTop ? .bottom : .top) {
            Color.white
            LinearGradient(colors: atTop ? [.white, .white.opacity(0)] : [.white.opacity(0), .white],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: Self.fade)
                .offset(y: atTop ? Self.fade : -Self.fade)
        }
        .ignoresSafeArea(edges: atTop ? .top : .bottom)
        .allowsHitTesting(false)
    }
}

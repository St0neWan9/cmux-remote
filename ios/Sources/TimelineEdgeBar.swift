import SwiftUI

/// The conversation's header or composer: a bar in the safe area whose own paint is frosted and
/// dissolves into the page past its inner edge.
///
/// The treatment lives on the bar, never on a row. A per-row layer effect rasterizes the row, which
/// stops the vendored text view from drawing its selection. The system's own soft edge effect is
/// asked for as well, but nothing depends on it: it renders weakly on some OS builds, and
/// Reduce Transparency drops it entirely.
struct TimelineEdgeBar<Bar: View>: ViewModifier {
    let edge: VerticalEdge
    @ViewBuilder let bar: () -> Bar

    /// How far past the bar the rows dissolve. The bar's own inset grows by the same amount, so the
    /// dissolve happens over ground the bar already owns and no message is buried under it.
    private static var fade: CGFloat { 16 }

    private var atTop: Bool { edge == .top }

    func body(content: Content) -> some View {
        if #available(iOS 26, *) {
            content.scrollEdgeEffectStyle(.soft, for: .vertical).safeAreaBar(edge: edge, spacing: 0) { paintedBar }
        } else {
            content.safeAreaInset(edge: edge, spacing: 0) { paintedBar }
        }
    }

    private var paintedBar: some View {
        bar()
            .padding(.bottom, atTop ? Self.fade : 0)
            .padding(.top, atTop ? 0 : Self.fade)
            .background(alignment: atTop ? .bottom : .top) { paint }
    }

    /// Frosted where the system still gives a material, with a plain gradient underneath it, so the
    /// dissolve survives Reduce Transparency and every OS version.
    private var paint: some View {
        ZStack(alignment: atTop ? .bottom : .top) {
            Rectangle().fill(.ultraThinMaterial)
                .mask(LinearGradient(colors: atTop ? [.white, .white, .clear] : [.clear, .white, .white],
                                     startPoint: .top, endPoint: .bottom))
            LinearGradient(colors: atTop ? [.white, .clear] : [.clear, .white],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: Self.fade)
                .offset(y: atTop ? Self.fade : -Self.fade)
        }
        .ignoresSafeArea(edges: atTop ? .top : .bottom)
        .allowsHitTesting(false)
    }
}

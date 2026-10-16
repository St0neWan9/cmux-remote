import SwiftUI

/// Fades and blurs the timeline where it passes under the header and the composer.
struct SoftScrollEdges: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26, *) { content.scrollEdgeEffectStyle(.soft, for: .vertical) }
        else { content }
    }
}

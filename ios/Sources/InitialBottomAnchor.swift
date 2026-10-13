import SwiftUI

/// A conversation opens at its latest message, without pinning a short one to the bottom.
struct InitialBottomAnchor: ViewModifier {
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *) { content.defaultScrollAnchor(.bottom, for: .initialOffset) } else { content }
    }
}

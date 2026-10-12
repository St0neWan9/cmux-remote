import SwiftUI

/// Keep automatic following separate from actual user scrolling and deceleration.
struct TimelineScrollInteraction: ViewModifier {
    @Binding var userScrolling: Bool
    @Binding var atLatest: Bool
    let latestVisible: Bool
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollPhaseChange { _, phase in
                switch phase {
                case .tracking: userScrolling = true
                case .interacting, .decelerating: userScrolling = true; atLatest = false
                case .idle: userScrolling = false; atLatest = latestVisible
                case .animating: break
                @unknown default: break
                }
            }
        } else {
            content.simultaneousGesture(DragGesture().onChanged { _ in userScrolling = true; atLatest = false }
                .onEnded { _ in userScrolling = false; atLatest = latestVisible })
        }
    }
}

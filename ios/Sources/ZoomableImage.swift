import SwiftUI

/// A preview image that answers the pinching, dragging and double taps a photo viewer is expected to
/// take, without letting the picture leave the page.
struct ZoomableImage: View {
    let image: UIImage
    let accessibilityName: String
    /// Close enough to fill the page on a double tap, without hiding what is around it.
    private static let doubleTapScale: CGFloat = 2.5
    private static let maximumScale: CGFloat = 6
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1
    @State private var offset: CGSize = .zero
    @GestureState private var pan: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let shown = min(Self.maximumScale, max(1, scale * pinch))
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(shown)
                .offset(clamped(CGSize(width: offset.width + pan.width, height: offset.height + pan.height), scale: shown, in: proxy.size))
                // A drag anywhere on the picture moves it; the page keeps its own edge swipe because this
                // gesture starts inside the image, not at the screen's edge.
                .gesture(pinchGesture(shown: shown))
                .simultaneousGesture(panGesture(in: proxy.size))
                .onTapGesture(count: 2) { toggleZoom() }
                .contentShape(Rectangle())
                .accessibilityLabel(accessibilityName)
                .animation(.interactiveSpring(response: 0.28, dampingFraction: 0.86), value: scale)
        }
        .onDisappear { reset() }
    }
    private func pinchGesture(shown: CGFloat) -> some Gesture {
        MagnifyGesture()
            .updating($pinch) { value, state, _ in state = value.magnification }
            .onEnded { value in
                // The pinch's own magnification is folded in here; `pinch` has already sprung back.
                scale = min(Self.maximumScale, max(1, scale * value.magnification))
                if scale == 1 { offset = .zero }
            }
    }
    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .updating($pan) { value, state, _ in
                guard scale > 1 else { return }
                state = value.translation
            }
            .onEnded { value in
                guard scale > 1 else { return }
                offset = clamped(CGSize(width: offset.width + value.translation.width, height: offset.height + value.translation.height), scale: scale, in: size)
            }
    }
    private func toggleZoom() {
        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.86)) {
            if scale > 1 { scale = 1; offset = .zero } else { scale = Self.doubleTapScale }
        }
    }
    /// How far the picture may move before it would show a gap along an edge.
    private func clamped(_ proposed: CGSize, scale: CGFloat, in size: CGSize) -> CGSize {
        let limitX = max(0, (size.width * scale - size.width) / 2)
        let limitY = max(0, (size.height * scale - size.height) / 2)
        return CGSize(width: min(limitX, max(-limitX, proposed.width)), height: min(limitY, max(-limitY, proposed.height)))
    }
    private func reset() {
        scale = 1; offset = .zero
    }
}

import SwiftUI

/// Blur only the message ink that enters the header; the page itself stays white.
struct HeaderContentEffect: ViewModifier {
    func body(content: Content) -> some View {
        content.visualEffect { effect, geometry in
            let frame = geometry.frame(in: .named("chatTimeline"))
            let top = Float(frame.minY)
            // Only rows reaching into the header and status bar area are rasterized for the blur; rows below scroll
            // without an offscreen pass, and rows far above are not built by the lazy timeline at all.
            let underHeader = frame.minY < 10 && frame.maxY > -400
            return effect
                .layerEffect(ShaderLibrary.headerBlurHorizontal(.float(top)), maxSampleOffset: CGSize(width: 11, height: 0), isEnabled: underHeader)
                .layerEffect(ShaderLibrary.headerBlurVertical(.float(top)), maxSampleOffset: CGSize(width: 0, height: 11), isEnabled: underHeader)
        }
    }
}

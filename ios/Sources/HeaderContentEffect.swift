import SwiftUI

/// Blur only the message ink that enters the header; the page itself stays white.
struct HeaderContentEffect: ViewModifier {
    func body(content: Content) -> some View {
        content.visualEffect { effect, geometry in
            let top = Float(geometry.frame(in: .named("chatTimeline")).minY)
            return effect
                .layerEffect(ShaderLibrary.headerBlurHorizontal(.float(top)), maxSampleOffset: CGSize(width: 20, height: 0))
                .layerEffect(ShaderLibrary.headerBlurVertical(.float(top)), maxSampleOffset: CGSize(width: 0, height: 20))
        }
    }
}

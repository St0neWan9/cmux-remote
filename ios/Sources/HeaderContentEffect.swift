import SwiftUI

/// Blur only the message ink that enters the header or the composer area; the page itself stays white.
struct HeaderContentEffect: ViewModifier {
    /// The visible bottom edge in the timeline's coordinates; content below it is under the composer.
    var bottom: CGFloat = .infinity
    func body(content: Content) -> some View {
        content.visualEffect { effect, geometry in
            let frame = geometry.frame(in: .named("chatTimeline"))
            let top = Float(frame.minY)
            // Only rows reaching into the header or composer area are rasterized for the blur; rows in between
            // scroll without an offscreen pass, and rows far outside are not built by the lazy timeline at all.
            // A layer effect rasterizes the whole row; past the GPU texture limit it draws nothing,
            // so a very tall row scrolls unblurred rather than as a blank page.
            let rasterizable = frame.height < 3_000
            let underHeader = rasterizable && frame.minY < 10 && frame.maxY > -400
            let underFooter = rasterizable && bottom.isFinite && frame.maxY > bottom - 10 && frame.minY < bottom + 400
            return effect
                .layerEffect(ShaderLibrary.headerBlurHorizontal(.float(top)), maxSampleOffset: CGSize(width: 11, height: 0), isEnabled: underHeader)
                .layerEffect(ShaderLibrary.headerBlurVertical(.float(top)), maxSampleOffset: CGSize(width: 0, height: 11), isEnabled: underHeader)
                .layerEffect(ShaderLibrary.footerBlurHorizontal(.float(top), .float(Float(bottom))), maxSampleOffset: CGSize(width: 11, height: 0), isEnabled: underFooter)
                .layerEffect(ShaderLibrary.footerBlurVertical(.float(top), .float(Float(bottom))), maxSampleOffset: CGSize(width: 0, height: 11), isEnabled: underFooter)
        }
    }
}

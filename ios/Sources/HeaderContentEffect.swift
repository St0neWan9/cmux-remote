import SwiftUI

/// Blur only the message ink that enters the header or the composer area; the page itself stays white.
struct HeaderContentEffect: ViewModifier {
    /// Past this height a row is not rasterized at all: the offscreen texture would exceed what the GPU can
    /// hold, and the row would draw nothing. The modifier is not attached instead, so the row still draws.
    static let rasterLimit: CGFloat = 3_000
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
            let rasterizable = frame.height < Self.rasterLimit
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

/// Applies the blur to a row, or leaves it alone where the row holds a control that must stay interactive or is
/// too tall to rasterize.
///
/// There is no way to turn the effect off from inside it: a `visualEffect` rasterizes the subtree it wraps
/// whether or not its layer effects are enabled, and a rasterized `TextField` becomes a placeholder, while a
/// row past the GPU texture limit draws nothing at all. The modifier must therefore not be attached at all.
///
/// The height is kept here, not by the timeline: expanding a group changes one row, and that must not
/// recompute the whole page.
struct BlurUnless: ViewModifier {
    let disabled: Bool
    let bottom: CGFloat
    /// Only crosses the threshold once per resize: writing every measured height would re-lay out the row on
    /// each pass, which a page of expanded tool groups turned into a freeze.
    @State private var tooTall = true
    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { measured in
                let tall = measured >= HeaderContentEffect.rasterLimit
                if tall != tooTall { tooTall = tall }
            }
            .modifier(ConditionalHeaderBlur(enabled: !disabled && !tooTall, bottom: bottom))
    }
}

/// The effect itself, attached only when the row can be rasterized.
private struct ConditionalHeaderBlur: ViewModifier {
    let enabled: Bool
    let bottom: CGFloat
    func body(content: Content) -> some View {
        if enabled { content.modifier(HeaderContentEffect(bottom: bottom)) } else { content }
    }
}

/// The edge blur for one line of a form, or nothing outside a conversation.
struct EdgeBlur: ViewModifier {
    let bottom: CGFloat?
    func body(content: Content) -> some View {
        if let bottom { content.modifier(HeaderContentEffect(bottom: bottom)) } else { content }
    }
}

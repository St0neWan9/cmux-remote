import SwiftUI

/// The edge blur is now the bar's own material. Message rows are no longer rasterized for a shader: a page of
/// long messages and expanded tool groups turned that into seconds of layout and, at times, a killed app.
struct EdgeBlur: ViewModifier {
    let bottom: CGFloat?
    func body(content: Content) -> some View { content }
}

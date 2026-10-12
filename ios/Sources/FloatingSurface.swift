import SwiftUI

/// White surfaces remain distinct through a soft shadow instead of a gray page background.
struct FloatingSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.frame(maxWidth: .infinity, alignment: .leading)
            .padding(MobileDesign.surfaceInset)
            .background(Color.white, in: RoundedRectangle(cornerRadius: MobileDesign.surfaceRadius))
            .overlay(RoundedRectangle(cornerRadius: MobileDesign.surfaceRadius).stroke(MobileDesign.outline, lineWidth: 0.5))
            .shadow(color: MobileDesign.shadow, radius: 14, y: 4)
    }
}

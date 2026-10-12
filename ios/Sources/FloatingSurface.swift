import SwiftUI

/// White surfaces remain distinct through a soft shadow instead of a gray page background.
struct FloatingSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(16).background(Color.white, in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Color.black.opacity(0.045), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.055), radius: 14, y: 4)
    }
}

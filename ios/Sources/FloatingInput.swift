import SwiftUI

/// Inputs share card edges and padding while retaining native text-field behavior.
struct FloatingInput: ViewModifier {
    func body(content: Content) -> some View {
        content.padding(.horizontal, MobileDesign.surfaceInset).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: MobileDesign.controlHeight, alignment: .leading)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(MobileDesign.outline, lineWidth: 0.5))
    }
}

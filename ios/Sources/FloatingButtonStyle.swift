import SwiftUI

/// Capsule actions use the same white surface and shadow as the floating navigation.
struct FloatingButtonStyle: ButtonStyle {
    var prominent = false
    var fullWidth = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let foreground = configuration.role == .destructive ? Color.red : (prominent ? Color.white : Color.primary)
        configuration.label.font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .padding(.horizontal, MobileDesign.surfaceInset).padding(.vertical, 12)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: MobileDesign.controlHeight)
            .foregroundStyle(enabled ? foreground : Color.secondary)
            .background(prominent && enabled ? MobileDesign.accent : Color.white, in: Capsule())
            .overlay(Capsule().stroke(MobileDesign.outline, lineWidth: 0.5))
            .shadow(color: MobileDesign.shadow, radius: 10, y: 3)
            .opacity(enabled ? (configuration.isPressed ? 0.65 : 1) : 0.45)
    }
}

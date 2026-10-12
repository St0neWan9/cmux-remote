import SwiftUI

/// A consistent 44-point target for navigation and other floating icon controls.
struct FloatingIconStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Color.primary)
            .frame(width: MobileDesign.controlHeight, height: MobileDesign.controlHeight)
            .background(Color.white, in: Circle())
            .shadow(color: MobileDesign.shadow, radius: 12, y: 3)
            .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
    }
}

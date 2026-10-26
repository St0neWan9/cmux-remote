import SwiftUI

/// A consistent 44-point target for navigation and other floating icon controls.
struct FloatingIconStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        let label = configuration.label
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(Color.primary)
            .frame(width: MobileDesign.controlHeight, height: MobileDesign.controlHeight)
            .opacity(enabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
        return Group {
            if #available(iOS 26.0, *) {
                // The system's own glass, exactly what the sheets' toolbar buttons use, so the app does not
                // draw an imitation of it.
                label.glassEffect(.regular.interactive(), in: .circle)
            } else {
                label.background(Color.white, in: Circle()).shadow(color: MobileDesign.shadow, radius: 12, y: 3)
            }
        }
    }
}

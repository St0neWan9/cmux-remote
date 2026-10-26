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

/// The same look for a control that is not a `Button` (a `Menu` label, an icon inside a row): the system's glass on
/// iOS 26, the app's white circle on older systems.
struct FloatingGlassCircle: ViewModifier {
    var size: CGFloat = MobileDesign.controlHeight
    func body(content: Content) -> some View {
        Group {
            if #available(iOS 26.0, *) {
                content.frame(width: size, height: size).glassEffect(.regular, in: .circle)
            } else {
                content.frame(width: size, height: size).background(Color.white, in: Circle())
                    .shadow(color: MobileDesign.shadow, radius: 12, y: 3)
            }
        }
    }
}

extension View {
    /// One way for every floating icon button to be pressed. The style draws the system's glass (non-interactive,
    /// so it never competes with the button's tap) as a fixed circle; the system's `.glass` button style sizes and
    /// shapes itself from the label, which made these controls inconsistent.
    func floatingIconButton() -> some View { buttonStyle(FloatingIconStyle()) }
}

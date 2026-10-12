import SwiftUI

/// Capsule actions use the same white surface and shadow as the floating navigation.
struct FloatingButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.subheadline.weight(.medium)).padding(.horizontal, 16).padding(.vertical, 12)
            .foregroundStyle(enabled ? (configuration.role == .destructive ? Color.red : Color.accentColor) : Color.secondary)
            .background(Color.white, in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(0.05), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.055), radius: 10, y: 3)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

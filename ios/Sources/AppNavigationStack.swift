import SwiftUI

/// Keeps system navigation transitions and edge-back gestures beneath floating headers.
struct AppNavigationStack<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        NavigationStack {
            content().background(InteractivePopInstaller())
        }.tint(MobileDesign.accent)
    }
}

import SwiftUI

/// Shared white canvas and floating navigation for the companion's utility screens.
struct WhitePage<Content: View>: View {
    let title: String
    var showsBack = true
    /// A custom back action in the same place, for pages that are not pushed (e.g. adding a Mac over the list).
    var back: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color.white.ignoresSafeArea())
            .background(InteractivePopInstaller())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    if showsBack || back != nil {
                        Button { if let back { back() } else { dismiss() } } label: {
                            Image(systemName: "chevron.left")
                        }.buttonStyle(FloatingIconStyle()).accessibilityLabel(String(localized: "page.back"))
                            .accessibilityIdentifier("page.back")
                    } else { Color.clear.frame(width: 44, height: 44) }
                    Text(title).font(.headline).multilineTextAlignment(.center).lineLimit(2).frame(maxWidth: .infinity)
                    Color.clear.frame(width: 44, height: 44)
                }.padding(.horizontal, MobileDesign.pageInset).padding(.vertical, 8).background(Color.white)
            }.environment(\.colorScheme, .light)
            // A page that replaces the root has no stack entry to pop, so it carries the edge swipe itself.
            .modifier(ConditionalEdgeBackSwipe(back: back))
            .accessibilityAction(.escape) { if showsBack { dismiss() } }
    }
}

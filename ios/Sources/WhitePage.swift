import SwiftUI

/// Shared white canvas and floating navigation for the companion's utility screens.
struct WhitePage<Content: View>: View {
    /// How the page is left: a pushed page slides back, a presented page closes at the top right.
    enum Dismissal { case back, close, none }
    let title: String
    var dismissal: Dismissal = .back
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
                    if dismissal == .back {
                        Button { if let back { back() } else { dismiss() } } label: {
                            Image(systemName: "chevron.left")
                        }.floatingIconButton().accessibilityLabel(String(localized: "page.back"))
                            .accessibilityIdentifier("page.back")
                    } else { Color.clear.frame(width: 44, height: 44) }
                    Text(title).font(.headline).multilineTextAlignment(.center).lineLimit(2).frame(maxWidth: .infinity)
                    if dismissal == .close {
                        Button { if let back { back() } else { dismiss() } } label: {
                            Image(systemName: "xmark")
                        }.floatingIconButton().accessibilityLabel(String(localized: "page.close"))
                            .accessibilityIdentifier("page.close")
                    } else { Color.clear.frame(width: 44, height: 44) }
                }.padding(.horizontal, MobileDesign.pageInset).padding(.vertical, 8).background(Color.white)
            }.environment(\.colorScheme, .light)
            // A page that replaces the root has no stack entry to pop, so it carries the edge swipe itself.
            .modifier(ConditionalEdgeBackSwipe(back: dismissal == .back ? { if let back { back() } else { dismiss() } } : nil))
            .accessibilityAction(.escape) { if dismissal != .none { if let back { back() } else { dismiss() } } }
    }
}

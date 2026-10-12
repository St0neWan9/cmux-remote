import SwiftUI

/// Shared white canvas and floating navigation for the companion's utility screens.
struct WhitePage<Content: View>: View {
    let title: String
    var showsBack = true
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        content().background(Color.white.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    if showsBack {
                        Button { dismiss() } label: {
                            Image(systemName: "chevron.left").font(.system(size: 20, weight: .medium))
                                .frame(width: 44, height: 44).background(Color.white, in: Circle())
                                .shadow(color: .black.opacity(0.07), radius: 10, y: 3)
                        }.buttonStyle(.plain).accessibilityLabel(String(localized: "page.back"))
                    } else { Color.clear.frame(width: 44, height: 44) }
                    Text(title).font(.headline).frame(maxWidth: .infinity)
                    Color.clear.frame(width: 44, height: 44)
                }.padding(.horizontal, 18).padding(.vertical, 8).background(Color.white)
            }.environment(\.colorScheme, .light)
    }
}

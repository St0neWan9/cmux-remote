import SwiftUI

/// Keeps the list visible as a floating page while revealing its left drawer.
struct SideDrawer<Main: View, Drawer: View>: View {
    @Binding var isPresented: Bool
    var allowsEdgeOpening = true
    @ViewBuilder let main: () -> Main
    @ViewBuilder let drawer: () -> Drawer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var translation: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            let width = min(440, geometry.size.width * 0.77)
            let offset = max(0, min(width, (isPresented ? width : 0) + translation))
            ZStack(alignment: .leading) {
                Color.white.ignoresSafeArea()
                drawer()
                    .frame(width: width, height: geometry.size.height)
                    .opacity(offset > 0 ? 1 : 0)
                    .allowsHitTesting(isPresented)
                    .accessibilityHidden(!isPresented)
                    .simultaneousGesture(drag(width: width, opening: false))
                main()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .accessibilityHidden(isPresented)
                    .overlay {
                        if isPresented {
                            Button { setPresented(false) } label: {
                                Color.white.opacity(0.4).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityLabel(String(localized: "sidebar.close"))
                                .accessibilityIdentifier("sidebar.close")
                                .gesture(drag(width: width, opening: false))
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: offset > 0 ? 38 : 0, style: .continuous))
                    .shadow(color: .black.opacity(offset > 0 ? 0.13 : 0), radius: 24, x: -8, y: 0)
                    .offset(x: offset)
                if !isPresented && allowsEdgeOpening {
                    Color.clear.frame(width: 20).contentShape(Rectangle())
                        .gesture(drag(width: width, opening: true))
                        .accessibilityHidden(true)
                }
            }.clipped()
                .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9), value: isPresented)
                .accessibilityAction(.escape) { setPresented(false) }
        }.background(Color.white.ignoresSafeArea())
    }
    private func drag(width: CGFloat, opening: Bool) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .updating($translation) { value, current, _ in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                current = opening ? max(0, min(width, value.translation.width)) : max(-width, min(0, value.translation.width))
            }
            .onEnded { value in
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                let displacement = value.predictedEndTranslation.width
                if opening { setPresented(displacement > width * 0.25) }
                else if displacement < -width * 0.25 { setPresented(false) }
            }
    }
    private func setPresented(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9)) { isPresented = value }
    }
}

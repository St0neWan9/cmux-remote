import SwiftUI

/// Keeps the list visible as a floating page while revealing its left drawer.
struct SideDrawer<Main: View, Drawer: View>: View {
    @Binding var isPresented: Bool
    var allowsEdgeOpening = true
    @ViewBuilder let main: () -> Main
    @ViewBuilder let drawer: () -> Drawer
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var phase
    @State private var motion = DrawerDragState()

    var body: some View {
        GeometryReader { geometry in
            let width = min(440, geometry.size.width * 0.77)
            let offset = motion.resolvedOffset(isPresented: isPresented, width: width)
            let screenHeight = geometry.size.height + geometry.safeAreaInsets.top + geometry.safeAreaInsets.bottom
            let screenCenterOffset = (geometry.safeAreaInsets.bottom - geometry.safeAreaInsets.top) / 2
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
                    .clipShape(DrawerPanelShape(topInset: geometry.safeAreaInsets.top,
                        bottomInset: geometry.safeAreaInsets.bottom, cornerRadius: offset > 0 ? 38 : 0))
                    .overlay(alignment: .leading) {
                        if isPresented {
                            Button { setPresented(false) } label: {
                                Color.white.opacity(0.4).contentShape(Rectangle())
                            }.frame(width: max(0, geometry.size.width - offset), height: geometry.size.height).buttonStyle(.plain)
                                .accessibilityLabel(String(localized: "sidebar.close"))
                                .accessibilityIdentifier("sidebar.close")
                                .gesture(drag(width: width, opening: false))
                        }
                    }
                    .background {
                        RoundedRectangle(cornerRadius: offset > 0 ? 38 : 0, style: .continuous)
                            .fill(Color.white)
                            .frame(width: geometry.size.width, height: screenHeight)
                            .offset(y: screenCenterOffset)
                            .shadow(color: .black.opacity(offset > 0 ? 0.13 : 0), radius: 24, x: -8, y: 0)
                    }
                    .offset(x: offset)
                if !isPresented && allowsEdgeOpening {
                    // Narrower than the leading page inset: the edge strip must not sit over the header's first
                    // button, which takes the left part of that inset.
                    Color.clear.frame(width: 12).contentShape(Rectangle())
                        .gesture(drag(width: width, opening: true))
                        .accessibilityHidden(true)
                }
            }
                .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9), value: isPresented)
                .onChange(of: geometry.size) { _, _ in motion.cancel() }
                .accessibilityAction(.escape) { setPresented(false) }
        }.background(Color.white.ignoresSafeArea())
            .onChange(of: isPresented) { _, _ in motion.cancel() }
            .onChange(of: allowsEdgeOpening) { _, available in if !available { motion.cancel() } }
            .onChange(of: phase) { _, value in if value != .active { motion.cancel() } }
            .onDisappear { motion.cancel() }
    }
    private func drag(width: CGFloat, opening: Bool) -> some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { value in
                guard phase == .active, opening ? !isPresented : isPresented,
                      motion.offset != nil || abs(value.translation.width) > abs(value.translation.height) else { return }
                var transaction = Transaction(); transaction.disablesAnimations = true
                withTransaction(transaction) { motion.update(translation: value.translation.width, width: width, opening: opening) }
            }
            .onEnded { value in
                guard phase == .active, motion.offset != nil else { return }
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9)) {
                    isPresented = motion.finish(predictedTranslation: value.predictedEndTranslation.width,
                        width: width, opening: opening, current: isPresented,
                        horizontal: abs(value.translation.width) > abs(value.translation.height))
                }
            }
    }
    private func setPresented(_ value: Bool) {
        withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.9)) { motion.cancel(); isPresented = value }
    }
}

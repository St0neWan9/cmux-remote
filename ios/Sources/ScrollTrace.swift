import SwiftUI

/// Records why the conversation page moved in the few seconds after the reader opened or closed a card,
/// so a jump that cannot be reproduced elsewhere shows its cause on the diagnostics page.
@MainActor final class ScrollTrace {
    private var toggledAt: Date?
    private let window: TimeInterval = 5
    func toggled(_ state: String) {
        toggledAt = Date()
        diagLog(.info, category: "scroll", "card toggled \(state)")
    }
    /// Kept only inside the window after a toggle; following new messages otherwise scrolls on every update.
    func note(_ message: String) {
        guard let toggledAt, Date().timeIntervalSince(toggledAt) < window else { return }
        diagLog(.info, category: "scroll", message)
    }
}

/// Notes scroll offset jumps the app did not ask for, which only iOS 18 can observe.
struct ScrollJumpTrace: ViewModifier {
    let trace: ScrollTrace
    @ViewBuilder func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { old, new in
                if abs(new - old) > 40 { trace.note("offset \(Int(old)) -> \(Int(new))") }
            }
            .onScrollPhaseChange { _, phase in trace.note("phase \(phase)") }
        } else { content }
    }
}

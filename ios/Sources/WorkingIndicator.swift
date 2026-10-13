import SwiftUI

/// A conversation that is still running. Drawn by SwiftUI: a UIKit spinner stops drawing in lazy rows and the sliding drawer.
struct WorkingIndicator: View {
    var size: CGFloat = 16
    var body: some View {
        // The angle comes from the clock, so a row that is rebuilt or scrolled back in keeps turning.
        TimelineView(.animation) { context in
            let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 0.9) / 0.9
            Circle().trim(from: 0, to: 0.72)
                .stroke(Color.secondary, style: StrokeStyle(lineWidth: max(1.5, size / 8), lineCap: .round))
                .frame(width: size, height: size)
                .rotationEffect(.degrees(turn * 360))
        }
        .frame(width: size + 4, height: size + 4)
        .accessibilityElement().accessibilityLabel(String(localized: "chat.working")).accessibilityIdentifier("session.working")
    }
}

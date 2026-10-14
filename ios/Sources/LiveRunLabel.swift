import SwiftUI
import CmuxRemoteCore

/// The running turn's elapsed time, in both places the terminal's own line appears: beside the
/// spinner above the input box, and at the top of the reply in progress, where a divider closes it.
///
/// While the agent compacts its context the line says so instead, which is the only moment the
/// conversation appears stalled: the same elapsed time with no visible progress.
struct LiveRunLabel: View {
    let since: Date
    /// Whether the agent is compacting its context right now.
    var compacting = false
    /// The turn's own line at the top of the reply carries a divider beneath it; the composer row does not.
    var showsDivider = false
    /// The composer row already draws the app's own spinner beside this, so it adds no mark of its own.
    var showsMark = true
    var font: Font = .footnote
    var body: some View {
        // Only this label re-renders every second; the message list around it does not.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let line = HStack(spacing: 7) {
                if showsMark {
                    // A UIKit spinner cannot be drawn inside the header/footer blur layer; a symbol can.
                    Image(systemName: "hourglass").symbolEffect(.pulse, options: .repeating).foregroundStyle(.secondary)
                }
                Text(Self.line(compacting ? "chat.compacting" : "chat.running_duration",
                               seconds: max(0, Int(context.date.timeIntervalSince(since)))))
                    .foregroundStyle(.secondary).monospacedDigit()
            }.font(font)
            if showsDivider {
                VStack(alignment: .leading, spacing: 10) {
                    line
                    Rectangle().fill(Color.black.opacity(0.1)).frame(height: 0.5)
                }.padding(.top, 6)
            } else { line }
        }.accessibilityIdentifier("response.elapsed")
    }
    /// The same wording in both places, so the composer row and the reply's top line never disagree.
    static func line(_ key: String.LocalizationValue, seconds: Int) -> String {
        String.localizedStringWithFormat(String(localized: key), timer(seconds))
    }
    /// `47s` or `3m 47s`.
    static func timer(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds)s" }
        return String(format: "%dm %02ds", seconds / 60, seconds % 60)
    }
}

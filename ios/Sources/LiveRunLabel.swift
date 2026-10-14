import SwiftUI
import CmuxRemoteCore

/// The agent's own working line, rendered as the terminal prints it:
/// `✻ Blanching… (54s · ↓ 2.3k tokens)`.
///
/// The gerund and token count come from the terminal screen, so they refresh only as fast as the
/// preview does; the elapsed time is ticked locally so it stays live between reads.
struct LiveRunLabel: View {
    let since: Date
    /// The line as the terminal rendered it; nil before the agent prints one.
    var status: TuiAgentStatus?
    var body: some View {
        // Only this label re-renders every second; the timeline around it does not.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    // A UIKit spinner cannot be drawn inside the header/footer blur layer; a symbol can.
                    if let glyph = status?.glyph {
                        Text(glyph).font(.subheadline).foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "hourglass").symbolEffect(.pulse, options: .repeating).foregroundStyle(.secondary)
                    }
                    Text(line(at: context.date)).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                }
                Rectangle().fill(Color.black.opacity(0.1)).frame(height: 0.5)
            }.padding(.top, 6)
        }.accessibilityIdentifier("response.elapsed")
    }
    /// `Blanching… (54s · ↓ 2.3k tokens)`, falling back to the elapsed duration alone.
    private func line(at date: Date) -> String {
        let elapsed = max(0, Int(date.timeIntervalSince(since)))
        var parts = [Self.timer(elapsed)]
        if let tokens = status?.tokenCount {
            parts.append((status?.tokensAscending == true ? "↑ " : "↓ ") + tokens + " tokens")
        }
        let detail = parts.joined(separator: " · ")
        // Compaction takes the place of the activity word, at the same spot on the line.
        if status?.isCompacting == true { return "\(String(localized: "chat.compacting")) (\(detail))" }
        guard let activity = status?.activity else { return "(\(detail))" }
        return "\(activity) (\(detail))"
    }
    /// `54s` or `1m05s`, matching the terminal's own spelling.
    static func timer(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds)s" }
        return String(format: "%dm%02ds", seconds / 60, seconds % 60)
    }
}

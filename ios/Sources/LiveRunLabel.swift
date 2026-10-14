import SwiftUI
import CmuxRemoteCore

/// The running turn's elapsed time, directly above the input box.
///
/// While the agent compacts its context the line says so instead, which is the only moment the
/// conversation appears stalled: the same elapsed time with no visible progress.
struct LiveRunLabel: View {
    let since: Date
    /// Whether the agent is compacting its context right now.
    var compacting = false
    var body: some View {
        // Only this label re-renders every second; the message list around it does not.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 7) {
                Image(systemName: "hourglass").symbolEffect(.pulse, options: .repeating).foregroundStyle(.secondary)
                Text(String.localizedStringWithFormat(String(localized: compacting ? "chat.compacting" : "chat.running_duration"),
                                                      Self.timer(max(0, Int(context.date.timeIntervalSince(since))))))
                    .foregroundStyle(.secondary).monospacedDigit()
            }.font(.footnote)
        }.accessibilityIdentifier("response.elapsed")
    }
    /// `47s` or `3m 47s`.
    static func timer(_ seconds: Int) -> String {
        guard seconds >= 60 else { return "\(seconds)s" }
        return String(format: "%dm %02ds", seconds / 60, seconds % 60)
    }
}

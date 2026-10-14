import SwiftUI
import CmuxRemoteCore

/// How long a finished turn took, spelled as the terminal spells it: `Worked for 3m 47s`.
struct ResponseRunLabel: View {
    let seconds: Double
    let recorded: Bool
    private var duration: String { Self.compactDuration(max(0, seconds)) }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // A turn cut short by a queued prompt has no recorded duration, but its measured span reads the same way.
            Text(String.localizedStringWithFormat(String(localized: "chat.worked_duration"), duration))
                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            Rectangle().fill(Color.black.opacity(0.1)).frame(height: 0.5)
        }.padding(.top, 6).accessibilityIdentifier("response.duration")
    }
    /// `3m 47s`, the same spelling as the running line.
    static func compactDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return String.localizedStringWithFormat(String(localized: "chat.duration_seconds"), total) }
        if total < 3_600 { return String.localizedStringWithFormat(String(localized: "chat.duration_minutes"), total / 60, total % 60) }
        return String.localizedStringWithFormat(String(localized: "chat.duration_hours"), total / 3_600, (total % 3_600) / 60)
    }
}

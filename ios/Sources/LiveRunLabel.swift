import SwiftUI

/// Elapsed time of the reply in progress, shown where its finished duration will later appear.
struct LiveRunLabel: View {
    let since: Date
    var body: some View {
        // Only this label re-renders every second; the timeline around it does not.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = Duration.seconds(max(0, context.date.timeIntervalSince(since))).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2))
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.mini)
                    Text(String.localizedStringWithFormat(String(localized: "chat.elapsed_duration"), elapsed)).monospacedDigit()
                }.font(.subheadline).foregroundStyle(.secondary)
                Rectangle().fill(Color.black.opacity(0.1)).frame(height: 0.5)
            }.padding(.top, 6)
        }.accessibilityIdentifier("response.elapsed")
    }
}

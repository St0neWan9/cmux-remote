import SwiftUI
import CmuxRemoteCore

struct ResponseRunLabel: View {
    let seconds: Double
    let recorded: Bool
    private var duration: String {
        Duration.seconds(max(0, seconds)).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .wide, maximumUnitCount: 2))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String.localizedStringWithFormat(String(localized: recorded ? "chat.ran_duration" : "chat.estimated_duration"), duration))
                .font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            Rectangle().fill(Color.black.opacity(0.1)).frame(height: 0.5)
        }.padding(.top, 6).accessibilityIdentifier("response.duration")
    }
}

import SwiftUI
import CmuxRemoteCore

/// Transcript actions operate on committed text, and never start a new provider request.
struct ResponseFooter: View {
    let response: ConversationResponse
    let text: String
    let quote: (String) -> Void
    @State private var copied = false
    var body: some View {
        // Equal boxes still look uneven: copy's back square rides high and share's box sits low under its arrow.
        HStack(spacing: 0) {
            Button {
                UIPasteboard.general.string = text; copied = true
            } label: { Image(systemName: copied ? "checkmark" : "square.on.square").offset(y: copied ? 0 : 2.0 / 3).frame(width: 36, height: 44) }
                .accessibilityLabel(String(localized: copied ? "chat.copied" : "chat.copy"))
                .accessibilityIdentifier("response.copy")
            ShareLink(item: text) { Image(systemName: "square.and.arrow.up").offset(y: -1.5).frame(width: 36, height: 44) }
                .accessibilityLabel(String(localized: "chat.share")).accessibilityIdentifier("response.share")
            Button { quote(text) } label: { Image(systemName: "text.quote").frame(width: 36, height: 44) }
                .accessibilityLabel(String(localized: "chat.quote")).accessibilityIdentifier("response.quote")
            if let date = response.completedAt {
                Text(date, format: Calendar.current.isDateInToday(date)
                     ? .dateTime.hour().minute()
                     : .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                    .font(.caption).monospacedDigit().padding(.leading, 10)
                    .accessibilityLabel(String(localized: "chat.response_time") + " " + date.formatted())
            }
            Spacer(minLength: 0)
        }.font(.system(size: 16)).foregroundStyle(.secondary).buttonStyle(.plain)
            // The targets centre their glyphs; pull the row back and up so the glyphs sit near the reply text.
            .padding(.leading, -9).padding(.top, -8).padding(.bottom, 6)
    }
}

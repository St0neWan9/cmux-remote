import SwiftUI
import CmuxRemoteCore

/// Transcript actions operate on committed text, and never start a new provider request.
struct ResponseFooter: View {
    let response: ConversationResponse
    let text: String
    let quote: (String) -> Void
    @State private var copied = false
    var body: some View {
        HStack(spacing: 18) {
            Button {
                UIPasteboard.general.string = text; copied = true
            } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: 30, height: 44) }
                .accessibilityLabel(String(localized: copied ? "chat.copied" : "chat.copy"))
                .accessibilityIdentifier("response.copy")
            ShareLink(item: text) { Image(systemName: "square.and.arrow.up").frame(width: 30, height: 44) }
                .accessibilityLabel(String(localized: "chat.share")).accessibilityIdentifier("response.share")
            Button { quote(text) } label: { Image(systemName: "text.quote").frame(width: 30, height: 44) }
                .accessibilityLabel(String(localized: "chat.quote")).accessibilityIdentifier("response.quote")
            if let date = response.completedAt {
                Text(date, format: Calendar.current.isDateInToday(date)
                     ? .dateTime.hour().minute()
                     : .dateTime.month(.twoDigits).day(.twoDigits).hour().minute())
                    .font(.caption).monospacedDigit()
                    .accessibilityLabel(String(localized: "chat.response_time") + " " + date.formatted())
            }
            Spacer(minLength: 0)
        }.font(.system(size: 16)).foregroundStyle(.secondary).buttonStyle(.plain)
            .padding(.top, 6).padding(.bottom, 10)
    }
}

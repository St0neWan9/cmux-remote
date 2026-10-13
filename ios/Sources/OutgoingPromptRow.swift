import SwiftUI
import CmuxRemoteCore

/// A sent prompt drawn as the user's bubble until the transcript's own copy replaces it.
struct OutgoingPromptRow: View {
    let prompt: OutgoingPrompt
    var body: some View {
        VStack(alignment: .trailing, spacing: 7) {
            HStack(alignment: .top) {
                Spacer(minLength: 44)
                VStack(alignment: .leading, spacing: 8) {
                    if prompt.imageCount > 0 {
                        Label(String.localizedStringWithFormat(String(localized: "chat.outgoing.images"), prompt.imageCount), systemImage: "photo").font(.subheadline)
                    }
                    if !prompt.text.isEmpty { Text(prompt.text).font(.body).lineSpacing(4).textSelection(.enabled) }
                }
                .foregroundStyle(Color.accentColor.opacity(prompt.delivery == .sending ? 0.6 : 1))
                .padding(.horizontal, 16).padding(.vertical, 13)
                .background(Color.accentColor.opacity(0.085), in: RoundedRectangle(cornerRadius: 24))
            }
            status.font(.caption).padding(.trailing, 6)
        }.padding(.top, 10).padding(.bottom, 22).accessibilityElement(children: .contain).accessibilityIdentifier("message.outgoing")
    }
    @ViewBuilder private var status: some View {
        // A UIKit spinner cannot be drawn inside the header/footer blur layer; a symbol can.
        switch prompt.delivery {
        case .sending:
            Label(String(localized: "chat.outgoing.sending"), systemImage: "arrow.up.circle").symbolEffect(.pulse, options: .repeating).foregroundStyle(.secondary)
        case .sent:
            Label(String(localized: "chat.outgoing.sent"), systemImage: "checkmark.circle").foregroundStyle(.secondary)
        case .unconfirmed:
            Label(String(localized: "chat.outgoing.unconfirmed"), systemImage: "exclamationmark.circle").foregroundStyle(.orange)
        }
    }
}

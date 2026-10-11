import SwiftUI
import CmuxAgentChat

/// Immutable rows distinguish the user's bubble from full-width agent prose.
struct MessageRow: View {
    let message: ChatMessage
    var body: some View {
        Group {
            if message.role == .user, case .prose(let value) = message.kind {
                HStack(alignment: .top) {
                    Spacer(minLength: 44)
                    Text(value.text).font(.body).lineSpacing(4).textSelection(.enabled)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .background(Color.accentColor.opacity(0.085), in: RoundedRectangle(cornerRadius: 24))
                }.padding(.top, 10).padding(.bottom, 22)
            } else {
                agentContent.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
            }
        }.accessibilityIdentifier("message." + message.id)
    }
    @ViewBuilder private var agentContent: some View {
        switch message.kind {
        case .prose(let value): MarkdownMessageView(text: value.text)
        case .thought(let value): DisclosureGroup(String(localized: "chat.thought")) { MarkdownMessageView(text: value.text) }
        case .toolUse(let value):
            DisclosureGroup(value.summary) { Text(value.output ?? value.inputDetail ?? "").font(.system(.callout, design: .monospaced)).textSelection(.enabled) }
        case .terminal(let value):
            DisclosureGroup(value.command) { Text(value.output ?? "").font(.system(.callout, design: .monospaced)).textSelection(.enabled) }
        case .fileEdit(let value):
            DisclosureGroup(value.filePath) { Text(value.unifiedDiff ?? value.operation.rawValue).font(.system(.callout, design: .monospaced)).textSelection(.enabled) }
        case .question(let value):
            VStack(alignment: .leading, spacing: 8) { Label(String(localized: "feed.title"), systemImage: "questionmark.bubble").font(.caption).foregroundStyle(.secondary); Text(value.prompt); ForEach(value.options) { Text($0.label) } }
                .padding(14).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        case .permissionRequest(let value):
            VStack(alignment: .leading, spacing: 8) { Label(value.title, systemImage: "hand.raised"); Text(value.subject).font(.system(.callout, design: .monospaced)) }
                .padding(14).background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
        case .status(let value): Text(value.detail ?? value.event.rawValue).font(.footnote).foregroundStyle(.secondary)
        default: Text(String(localized: "chat.other")).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

import SwiftUI
import CmuxAgentChat

struct MessageRow: View {
    let message: ChatMessage
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message.role == .user ? String(localized: "chat.you") : String(localized: "chat.agent")).font(.caption).foregroundStyle(.secondary)
            switch message.kind {
            case .prose(let value): Text(.init(value.text)).textSelection(.enabled)
            case .thought(let value): DisclosureGroup(String(localized: "chat.thought")) { Text(value.text).textSelection(.enabled) }
            case .toolUse(let value): DisclosureGroup(value.summary) { Text(value.output ?? value.inputDetail ?? "").font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            case .terminal(let value): DisclosureGroup(value.command) { Text(value.output ?? "").font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            case .fileEdit(let value): DisclosureGroup(value.filePath) { Text(value.unifiedDiff ?? value.operation.rawValue).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
            default: Text(String(localized: "chat.other")).font(.footnote).foregroundStyle(.secondary)
            }
        }.padding(.vertical, 6)
    }
}

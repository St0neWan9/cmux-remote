import SwiftUI
import CmuxAgentChat
import CmuxRemoteCore

/// Immutable rows distinguish the user's bubble from full-width agent prose.
struct MessageRow: View {
    let message: ChatMessage
    var projectRoot: String?
    var openFile: ((String) -> Void)?
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
    @ViewBuilder private func referenceButton(_ path: String) -> some View {
        if let relative = ProjectReference().relativePath(path, root: projectRoot), let openFile {
            Button { openFile(relative) } label: { Label(String(localized: "project.open_reference"), systemImage: "doc.text.magnifyingglass") }
                .buttonStyle(FloatingButtonStyle())
        }
    }
    @ViewBuilder private var agentContent: some View {
        switch message.kind {
        case .prose(let value): MarkdownMessageView(text: value.text)
        case .thought(let value): DisclosureGroup(String(localized: "chat.thought")) { MarkdownMessageView(text: value.text) }
        case .toolUse(let value):
            DisclosureGroup(value.summary) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(value.status.localizedTitle).font(.caption).foregroundStyle(.secondary)
                    if let input = value.inputDetail { Text(input).font(.system(.callout, design: .monospaced)).textSelection(.enabled) }
                    if let output = value.output { Text(output).font(.system(.callout, design: .monospaced)).textSelection(.enabled) }
                    ForEach(value.referencedPaths ?? [], id: \.self) { path in referenceButton(path) }
                }
            }
        case .terminal(let value):
            DisclosureGroup(value.command) {
                VStack(alignment: .leading, spacing: 10) {
                    if let seconds = value.durationSeconds, seconds.isFinite && seconds >= 0 { ResponseRunLabel(seconds: seconds, recorded: true) }
                    if let exit = value.exitCode { Text(String.localizedStringWithFormat(String(localized: "chat.exit_code"), exit)).font(.caption).foregroundStyle(exit == 0 ? Color.secondary : Color.red) }
                    Text(value.output ?? "").font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                }
            }
        case .fileEdit(let value):
            DisclosureGroup(value.filePath) {
                VStack(alignment: .leading, spacing: 10) { Text(value.unifiedDiff ?? "").font(.system(.callout, design: .monospaced)).textSelection(.enabled); referenceButton(value.filePath) }
            }
        case .question(let value):
            VStack(alignment: .leading, spacing: 8) { Label(String(localized: "feed.title"), systemImage: "questionmark.bubble").font(.caption).foregroundStyle(.secondary); Text(value.prompt); ForEach(value.options) { Text($0.label) } }
                .modifier(FloatingSurface())
        case .permissionRequest(let value):
            VStack(alignment: .leading, spacing: 8) { Label(value.title, systemImage: "hand.raised"); Text(value.subject).font(.system(.callout, design: .monospaced)) }
                .modifier(FloatingSurface())
        case .attachment(let value):
            VStack(alignment: .leading, spacing: 8) {
                Label(value.displayName ?? value.hostPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? String(localized: "chat.attachment"), systemImage: value.media == .image ? "photo" : "paperclip")
                if value.media == .file, let path = value.hostPath { referenceButton(path) }
                if value.media == .image { Text(String(localized: "chat.image_metadata")).font(.caption).foregroundStyle(.secondary) }
            }.modifier(FloatingSurface())
        case .status(let value): Text(value.detail ?? value.event.localizedTitle).font(.footnote).foregroundStyle(.secondary)
        default: Text(String(localized: "chat.other")).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

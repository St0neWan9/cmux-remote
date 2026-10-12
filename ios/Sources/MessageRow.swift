import SwiftUI
import CmuxAgentChat
import CmuxRemoteCore

/// Immutable rows distinguish the user's bubble from full-width agent prose.
struct MessageRow: View {
    let message: ChatMessage
    var projectRoot: String?
    var openFile: ((String) -> Void)?
    var openDetail: ((String, String) -> Void)?
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
    @ViewBuilder private func detailButton(_ field: String) -> some View {
        if let openDetail {
            Button(String(localized: "tool.detail.open")) { openDetail(message.id, field) }
                .font(.footnote).buttonStyle(.plain).accessibilityIdentifier("tool.detail." + message.id)
        }
    }
    @ViewBuilder private var agentContent: some View {
        switch message.kind {
        case .prose(let value): MarkdownMessageView(text: value.text)
        case .thought(let value): DisclosureGroup(String(localized: "chat.thought")) { MarkdownMessageView(text: value.text) }
        case .toolUse(let value):
            ToolDisclosure(title: value.summary, symbol: value.toolName.lowercased().contains("read") ? "book" : "magnifyingglass") {
                ToolDetailCard(title: value.toolName, status: value.status == .succeeded ? String(localized: "tool.card.success") : value.status.localizedTitle, failed: value.status == .failed) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let input = value.inputDetail, !input.isEmpty { ToolCodeBlock(text: input) }
                        if let output = value.output, !output.isEmpty { ToolCodeBlock(text: output) }
                        ForEach(value.referencedPaths ?? [], id: \.self) { path in referenceButton(path) }
                        detailButton(value.output == nil ? "input" : "output")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .terminal(let value):
            ToolDisclosure(title: value.command, symbol: "terminal") {
                ToolDetailCard(title: String(localized: "tool.card.shell"),
                               status: value.exitCode.map { $0 == 0 ? String(localized: "tool.card.success") : String.localizedStringWithFormat(String(localized: "chat.exit_code"), $0) } ?? String(localized: "chat.tool.running"),
                               failed: value.exitCode.map { $0 != 0 } ?? false) {
                    VStack(alignment: .leading, spacing: 12) {
                        ToolCodeBlock(text: "$ " + value.command)
                        if let output = value.output, !output.isEmpty { ToolCodeBlock(text: output).foregroundStyle(.secondary) }
                        detailButton(value.output == nil ? "input" : "output")
                        if let seconds = value.durationSeconds, seconds.isFinite && seconds >= 0 { ResponseRunLabel(seconds: seconds, recorded: true) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .fileEdit(let value):
            ToolDisclosure(title: value.filePath, symbol: "doc.text") {
                ToolDetailCard(title: String(localized: "project.diff")) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let diff = value.unifiedDiff, !diff.isEmpty { ToolCodeBlock(text: diff) }
                        referenceButton(value.filePath)
                        detailButton("diff")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
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

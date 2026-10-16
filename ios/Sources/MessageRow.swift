import SwiftUI
import CmuxAgentChat
import CmuxRemoteCore

/// Immutable rows distinguish the user's bubble from full-width agent prose.
struct MessageRow: View {
    let message: ChatMessage
    var projectRoot: String?
    var openFile: ((String) -> Void)?
    var images: [ConversationImageReference] = []
    var openImage: ((ConversationImageReference) -> Void)?
    var openDetail: ((String, String) -> Void)?
    var body: some View {
        Group {
            if message.role == .user, case .prose(let value) = message.kind {
                HStack(alignment: .top) {
                    Spacer(minLength: 44)
                    Text(PromptText.displayed(value.text)).font(.body).lineSpacing(4)
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 16).padding(.vertical, 13)
                        .background(Color.accentColor.opacity(0.085), in: RoundedRectangle(cornerRadius: 24))
                        .modifier(SelectableTextMenu(text: PromptText.displayed(value.text)))

                }.padding(.top, 10).padding(.bottom, 22)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    agentContent
                    imageButtons
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, isOperation ? 0 : 5)
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("message." + message.id)
    }
    /// Tool rows stack tightly; text keeps its breathing room.
    var isOperation: Bool {
        switch message.kind { case .prose, .thought: return false; default: return true }
    }
    @ViewBuilder private var imageButtons: some View {
        if let openImage {
            ForEach(images.filter { $0.messageID == message.id }) { image in
                Button { openImage(image) } label: { Label(String(localized: "image.history.open"), systemImage: "photo") }
                    .buttonStyle(FloatingButtonStyle()).accessibilityIdentifier("image.history." + image.id)
            }
        }
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
        // Reasoning between operations is part of the reply: shown in full, without a title or disclosure.
        case .thought(let value): MarkdownMessageView(text: value.text)
        case .toolUse(let value):
            ToolDisclosure(title: value.summary, symbol: value.toolName.lowercased().contains("read") ? "book" : "magnifyingglass", identifier: "tool.disclosure." + message.id) {
                ToolDetailCard(title: value.toolName, status: value.status == .succeeded ? String(localized: "tool.card.success") : value.status.localizedTitle, failed: value.status == .failed, completedAt: value.completedAt) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let input = value.inputDetail, !input.isEmpty { ToolCodeBlock(text: input) }
                        if let output = value.output, !output.isEmpty { ToolCodeBlock(text: output) }
                        ForEach(value.referencedPaths ?? [], id: \.self) { path in referenceButton(path) }
                        detailButton(value.output == nil ? "input" : "output")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .terminal(let value):
            // The agent describes every command in one line; the terminal shows that description above
            // the shell line, so the card leads with it and keeps the command as the detail.
            ToolDisclosure(title: value.summary ?? value.command, symbol: "terminal", identifier: "tool.disclosure." + message.id) {
                ToolDetailCard(title: String(localized: "tool.card.shell"),
                               status: value.exitCode.map { $0 == 0 ? String(localized: "tool.card.success") : String.localizedStringWithFormat(String(localized: "chat.exit_code"), $0) } ?? String(localized: "chat.tool.running"),
                               failed: value.exitCode.map { $0 != 0 } ?? false, completedAt: value.completedAt) {
                    VStack(alignment: .leading, spacing: 12) {
                        ToolCodeBlock(text: "$ " + value.command)
                        if let output = value.output, !output.isEmpty { ToolCodeBlock(text: output).foregroundStyle(.secondary) }
                        detailButton(value.output == nil ? "input" : "output")
                        if let seconds = value.durationSeconds, seconds.isFinite && seconds >= 0 { ResponseRunLabel(seconds: seconds, recorded: true) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        case .fileEdit(let value):
            ToolDisclosure(title: value.filePath, symbol: "doc.text", identifier: "tool.disclosure." + message.id) {
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
                if value.media == .image && !images.contains(where: { $0.messageID == message.id }) { Text(String(localized: "chat.image_metadata")).font(.caption).foregroundStyle(.secondary) }
            }.modifier(FloatingSurface())
        case .status(let value): Text(value.detail ?? value.event.localizedTitle).font(.footnote).foregroundStyle(.secondary)
        default: Text(String(localized: "chat.other")).font(.footnote).foregroundStyle(.secondary)
        }
    }
}

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
    /// The Feed request that may answer this question, when the agent is still waiting on it.
    var pendingQuestion: ConversationQuestions.Match?
    /// Whether an answer is on its way, so the card does not accept a second tap.
    var answering = false
    /// Sends the chosen labels for this question, in the question's own order.
    var answerQuestion: (([String]) -> Void)?
    /// What this reader chose here, when the transcript has not recorded it yet.
    var chosenAnswer: String?
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
        case .question where pendingQuestion.map { !$0.isFirst } ?? false:
            // A later question of a request still waiting: the first card already carries it in its form, so a
            // second copy would only repeat it. It shows again as a record once the request is answered.
            EmptyView()
        case .question(let value):
            // The same card answers on the phone and stays a record once the request is gone: only a currently
            // pending request for this exact prompt is offered, and it is answered through the Feed.
            VStack(alignment: .leading, spacing: 12) {
                Label(String(localized: "feed.title"), systemImage: "questionmark.bubble").font(.caption).foregroundStyle(.secondary)
                if let pendingQuestion, pendingQuestion.isFirst, let answerQuestion {
                    // The whole request is rendered on its first card, exactly as the Feed lists it: one reply
                    // carries one label per question, so a card cannot answer only its own.
                    // The form keeps its own identifiers: a container identifier would replace each control's.
                    FeedQuestionView(questions: pendingQuestion.questions, busy: answering) { answers in answerQuestion(answers) }
                } else {
                    Text(value.prompt)
                    // An answered question is a record of the choice, not a dead form: naming the answer is what
                    // the reader came back for, and only a still-unanswered card says it cannot be answered here.
                    if let selected = value.selectedOptionLabel ?? chosenAnswer {
                        Text(value.options.isEmpty ? selected : String.localizedStringWithFormat(String(localized: "chat.question.answered"), selected))
                            .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ForEach(value.options) { Text($0.label) }
                        Text(String(localized: "feed.question.unavailable")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }.modifier(FloatingSurface())
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

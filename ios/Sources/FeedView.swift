import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

struct FeedView: View {
    let client: RemoteClient
    @State private var model: FeedModel
    @Environment(\.scenePhase) private var phase
    init(client: RemoteClient) { self.client = client; _model = State(initialValue: FeedModel(client: client)) }
    var body: some View {
        let items = model.items.filter { model.showHistory || $0["status"].string == "pending" }.enumerated().map { FeedEntry(value: $0.element, fallbackIndex: $0.offset) }
        let busy = model.busy
        let loading = model.loading
        let error = model.error
        WhitePage(title: String(localized: "feed.title")) {
            ScrollView {
                VStack(alignment: .leading, spacing: MobileDesign.sectionGap) {
                    ActionRow {
                        Button(String(localized: "feed.pending")) { model.showHistory = false }.buttonStyle(FloatingButtonStyle(prominent: !model.showHistory)).accessibilityAddTraits(!model.showHistory ? .isSelected : [])
                        Button(String(localized: "feed.history")) { model.showHistory = true }.buttonStyle(FloatingButtonStyle(prominent: model.showHistory)).accessibilityAddTraits(model.showHistory ? .isSelected : [])
                    }.buttonStyle(FloatingButtonStyle())
                    if loading && items.isEmpty { ProgressView() }
                    else if items.isEmpty { Text(String(localized: "feed.empty")).foregroundStyle(.secondary) }
                    ForEach(items) { entry in
                        let item = entry.value
                        VStack(alignment: .leading, spacing: 12) {
                            Text(item["title"].string ?? item["tool_name"].string ?? String(localized: "feed.event")).font(.headline)
                            if let plan = item["plan"].string { MarkdownMessageView(text: plan) }
                            if let prompt = item["question_prompt"].string { Text(prompt) }
                            if let detail = item["tool_input"].string { Text(detail).font(.caption.monospaced()).textSelection(.enabled) }
                            if let text = item["text"].string ?? item["reason"].string { MarkdownMessageView(text: text) }
                            if let result = item["tool_result"].string {
                                if item["tool_result_is_error"].bool == true { Label(String(localized: "chat.tool.failed"), systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                                Text(result).font(.callout.monospaced()).textSelection(.enabled)
                            }
                            if item["tool_result_truncated"].bool == true || item["tool_input_truncated"].bool == true || item["plan_truncated"].bool == true { Text(String(localized: "project.truncated")).font(.caption).foregroundStyle(.secondary) }
                            if let feedback = item["decision"]["feedback"].string { Text(feedback).font(.callout).textSelection(.enabled) }
                            if let todos = item["todos"].array {
                                ForEach(Array(todos.enumerated()), id: \.offset) { _, todo in
                                    Label(todo["content"].string ?? "", systemImage: todo["state"].string == "completed" ? "checkmark.circle" : "circle").font(.callout)
                                }
                            }
                            let kind = item["kind"].string ?? ""
                            if item["status"].string == "pending" {
                                if kind == "permissionRequest" || kind == "exitPlan" {
                                    FeedDecisionControls(item: item, busy: busy || !client.canReplyFeed) { mode, feedback in Task { await model.reply(item, mode: mode, feedback: feedback) } }
                                } else if kind == "question" {
                                    FeedQuestionView(questions: item["questions"].array ?? [], busy: busy || !client.canReplyFeed) { answers in Task { await model.reply(item, selections: answers) } }
                                } else { Text(String(localized: "feed.unsupported")).font(.footnote).foregroundStyle(.secondary) }
                            } else {
                                Text(String(localized: item["status"].string == "expired" ? "feed.expired" : (item["status"].string == "resolved" ? "feed.resolved" : "feed.recorded"))).font(.caption).foregroundStyle(.secondary)
                                if let raw = item["decision"]["mode"].string, let mode = FeedDecisionMode(rawValue: raw) { Text(mode.localizedTitle).font(.footnote) }
                                if let answers = item["decision"]["selections"].array { ForEach(Array(answers.enumerated()), id: \.offset) { _, value in if let text = value.string { Text(text).font(.footnote) } } }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).modifier(FloatingSurface())
                    }
                    if let error { Text(error).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(MobileDesign.pageInset)
            }.refreshable { await model.refresh() }
        }.onDisappear { model.suspendReads() }
        .onChange(of: phase) { _, value in if value != .active { model.suspendReads() } }
        .task(id: phase) {
            guard phase == .active else { model.suspendReads(); return }; model.resumeReads()
            await model.observeChanges()
        }
    }
}

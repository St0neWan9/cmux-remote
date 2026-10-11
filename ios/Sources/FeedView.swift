import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

struct FeedView: View {
    let client: RemoteClient
    @State private var items: [JSONValue] = []
    @State private var error: String?
    @State private var busy = false
    var body: some View {
        List {
            if items.isEmpty { Text(String(localized: "feed.empty")).foregroundStyle(.secondary) }
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                VStack(alignment: .leading, spacing: 10) {
                    Text(item["title"].string ?? item["tool_name"].string ?? item["kind"].string ?? "")
                    if let plan = item["plan"].string { Text(.init(plan)) }
                    if let prompt = item["question_prompt"].string { Text(prompt) }
                    if let detail = item["tool_input"].string { Text(detail).font(.caption).textSelection(.enabled) }
                    let kind = item["kind"].string ?? ""
                    if kind == "permissionRequest" || kind == "exitPlan" {
                        HStack {
                            Button(String(localized: "feed.allow")) { Task { await reply(item, mode: kind == "permissionRequest" ? "once" : "manual") } }
                            Button(String(localized: "feed.deny"), role: .destructive) { Task { await reply(item, mode: "deny") } }
                        }.buttonStyle(.bordered).disabled(busy)
                    } else if kind == "question" {
                        FeedQuestionView(questions: item["questions"].array ?? [], busy: busy) { answers in Task { await reply(item, selections: answers) } }
                    }
                }
            }
            if let error { Text(error).foregroundStyle(.red) }
        }.navigationTitle(String(localized: "feed.title")).task { await refresh() }.refreshable { await refresh() }
    }
    private func refresh() async {
        do { let result = try await client.get("/v1/feed", as: JSONValue.self); items = (result["items"].array ?? []).filter { $0["status"].string == "pending" }; error = nil }
        catch { self.error = ErrorPresentation().message(error) }
    }
    private func reply(_ item: JSONValue, mode: String? = nil, selections: [String]? = nil) async {
        guard let id = item["request_id"].string, !busy else { return }; busy = true; defer { busy = false }
        var body: [String: JSONValue] = ["operation_id": .string(UUID().uuidString), "kind": item["kind"]]
        if let mode { body["mode"] = .string(mode) }; if let selections { body["selections"] = .array(selections.map(JSONValue.string)) }
        do { _ = try await client.post("/v1/feed/\(id)/reply", body: JSONValue.object(body), as: MutationReceipt.self); await refresh() }
        catch { self.error = ErrorPresentation().message(error) }
    }
}

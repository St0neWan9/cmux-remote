import SwiftUI
import CmuxRemoteClient
import CmuxRemoteCore

struct ToolDetailView: View {
    @State private var model: ToolDetailModel
    @State private var loadTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var phase
    init(reference: ToolDetailReference, sessionID: String, client: RemoteClient) {
        _model = State(initialValue: ToolDetailModel(reference: reference, fetch: {
            try await client.get("/v1/sessions/\(sessionID)/tool-detail", query: $0, as: ToolTextPage.self)
        }))
    }
    var body: some View {
        NavigationStack {
            WhitePage(title: String(localized: "tool.detail.title")) {
                VStack(alignment: .leading, spacing: 16) {
                    if model.reference.fields.count > 1 {
                        Picker(String(localized: "tool.detail.title"), selection: $model.field) {
                            ForEach(model.reference.fields, id: \.self) { field in Text(title(field)).tag(field) }
                        }.pickerStyle(.segmented).disabled(model.busy)
                    }
                    if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
                    if let page = model.page {
                        ScrollView {
                            if page.text.isEmpty { Text(String(localized: "tool.detail.empty")).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
                            else { ToolCodeBlock(text: page.text) }
                        }.id(page.contentID + ":" + String(page.offset)).frame(maxWidth: .infinity, maxHeight: .infinity)
                        HStack {
                            Button(String(localized: "tool.detail.previous")) { load(max(0, page.offset - 16_384), preserving: true) }.disabled(page.offset == 0 || model.busy)
                            Spacer()
                            Button(String(localized: "chat.refresh")) { load() }.disabled(model.busy)
                            Spacer()
                            Button(String(localized: "tool.detail.next")) { if let next = page.nextOffset { load(next, preserving: true) } }.disabled(page.nextOffset == nil || model.busy)
                        }.font(.subheadline).buttonStyle(FloatingButtonStyle())
                    } else {
                        if model.busy { ProgressView() }
                        else { Button(String(localized: "chat.refresh")) { load() }.buttonStyle(FloatingButtonStyle()) }
                        Spacer()
                    }
                }.padding(20)
            }
        }
        .onChange(of: model.field) { _, _ in load() }
        .task(id: phase) {
            guard phase == .active else { loadTask?.cancel(); model.suspend(); return }
            if model.page == nil { await model.load() }
        }
        .onDisappear { loadTask?.cancel(); model.suspend() }
    }
    private func load(_ offset: Int = 0, preserving: Bool = false) {
        loadTask?.cancel()
        loadTask = Task { await model.load(offset: offset, preserveRevision: preserving) }
    }
    private func title(_ field: String) -> String {
        switch field {
        case "input": String(localized: "tool.detail.input")
        case "output": String(localized: "tool.detail.output")
        default: String(localized: "project.diff")
        }
    }
}

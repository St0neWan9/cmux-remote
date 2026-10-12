import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

struct ProjectView: View {
    @State private var model: ProjectModel
    @Environment(\.scenePhase) private var phase
    init(session: SessionDescriptor, client: RemoteClient, initialPath: String = "") {
        _model = State(initialValue: ProjectModel(session: session, client: client, initialPath: initialPath))
    }
    var body: some View {
        let entries = model.entries
        let content = model.content
        let resource = model.resource
        let busy = model.busy
        let error = model.error
        WhitePage(title: String(localized: "project.title")) {
            ScrollView {
                VStack(alignment: .leading, spacing: MobileDesign.sectionGap) {
                    TextField(String(localized: "project.path"), text: $model.filePath).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .submitLabel(.go).onSubmit { Task { await model.load(.file) } }.accessibilityIdentifier("project.path")
                        .modifier(FloatingInput())
                    ActionRow {
                        Button(String(localized: "project.file")) { Task { await model.load(.file) } }.buttonStyle(FloatingButtonStyle(prominent: resource == .file)).disabled(model.filePath.isEmpty).accessibilityIdentifier("project.file")
                        Button(String(localized: "project.diff")) { Task { await model.load(.diff) } }.buttonStyle(FloatingButtonStyle(prominent: resource == .diff)).accessibilityIdentifier("project.diff")
                        Button(String(localized: "project.changes")) { Task { await model.load(.changes) } }.buttonStyle(FloatingButtonStyle(prominent: resource == .changes)).accessibilityIdentifier("project.changes")
                    }.buttonStyle(FloatingButtonStyle()).disabled(busy)
                    if busy { ProgressView() }
                    if let error { Text(error).foregroundStyle(.red) }
                    if resource == .changes {
                        if entries.isEmpty && !busy { Text(String(localized: "project.empty_changes")).foregroundStyle(.secondary) }
                        ForEach(entries) { change in
                            Button {
                                model.filePath = change.path; Task { await model.load(change.status.contains("D") ? .diff : .file) }
                            } label: {
                                HStack(alignment: .top, spacing: 12) {
                                    Text(change.status).font(.caption.monospaced()).foregroundStyle(.secondary)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(change.path).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                                        if let previous = change.previousPath { Text(previous + " → " + change.path).font(.caption).foregroundStyle(.secondary) }
                                    }
                                    Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                }.frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("project.change." + change.path)
                        }
                    } else {
                        if model.truncated { Label(String(localized: "project.truncated"), systemImage: "text.badge.minus").font(.footnote).foregroundStyle(.secondary) }
                        if content.isEmpty && !busy { Text(String(localized: "project.empty_content")).foregroundStyle(.secondary) }
                        Text(content).font(.system(.footnote, design: .monospaced)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        if !content.isEmpty {
                            ActionRow {
                                Button { UIPasteboard.general.string = content } label: { Label(String(localized: "project.copy"), systemImage: "doc.on.doc") }
                                ShareLink(item: content) { Label(String(localized: "project.share"), systemImage: "square.and.arrow.up") }
                            }.buttonStyle(FloatingButtonStyle())
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(MobileDesign.pageInset)
            }
        }.onDisappear { model.suspendReads() }
        .onChange(of: phase) { _, value in if value != .active { model.suspendReads() } }
        .task(id: phase) {
            guard phase == .active else { model.suspendReads(); return }
            model.resumeReads(); await model.reload()
        }
    }
}

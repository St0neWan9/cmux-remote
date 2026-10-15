import SwiftUI
import CmuxRemoteCore

/// One folder inside a launch root: start here with the chosen agent, or open a subfolder.
struct StartFolderView: View {
    @Bindable var model: StartSessionModel
    let root: LaunchDirectory
    /// Relative to the root; empty for the root itself.
    let path: String
    let onStarted: (_ hostID: String, _ surfaceID: String?) -> Void
    @State private var listing: LaunchDirectoryListing?
    @State private var listingError: String?
    var body: some View {
        WhitePage(title: path.isEmpty ? URL(fileURLWithPath: root.path).lastPathComponent : URL(fileURLWithPath: path).lastPathComponent) {
            ScrollView {
                VStack(alignment: .leading, spacing: MobileDesign.sectionGap) {
                    VStack(alignment: .leading, spacing: MobileDesign.rowGap) {
                        Text(path.isEmpty ? root.path : root.path + "/" + path).font(.footnote.monospaced()).foregroundStyle(.secondary)
                            .lineLimit(3).truncationMode(.middle).textSelection(.enabled)
                        Picker(String(localized: "start.agent"), selection: $model.agent) {
                            ForEach(LaunchAgent.allCases, id: \.self) { agent in Text(agent.rawValue.capitalized).tag(agent) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("start.agent")
                        TextField(model.agent.requiresPrompt ? String(localized: "start.prompt_required") : String(localized: "start.prompt_optional"), text: $model.prompt, axis: .vertical)
                            .lineLimit(2...6).padding(12)
                            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                            .accessibilityIdentifier("start.prompt")
                        if model.agent.requiresPrompt {
                            Text(String(localized: "start.prompt_codex_hint")).font(.footnote).foregroundStyle(.secondary)
                        }
                        Button { Task { await start(fresh: false) } } label: {
                            Label(model.uncertain ? String(localized: "start.retry") : String(localized: "start.here"), systemImage: "play.fill")
                        }.buttonStyle(FloatingButtonStyle(prominent: true, fullWidth: true)).disabled(!model.canStart)
                            .accessibilityIdentifier("start.here")
                        if model.uncertain {
                            Button(String(localized: "start.fresh")) { Task { await start(fresh: true) } }
                                .buttonStyle(FloatingButtonStyle(fullWidth: true)).disabled(model.starting).accessibilityIdentifier("start.fresh")
                        }
                        if model.starting { ProgressView(String(localized: "start.starting")).frame(maxWidth: .infinity) }
                        if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(localized: "start.subfolders")).font(.headline)
                        if let listing {
                            if listing.directories.isEmpty { Text(String(localized: "start.no_subfolders")).font(.footnote).foregroundStyle(.secondary) }
                            ForEach(listing.directories, id: \.self) { name in
                                NavigationLink {
                                    StartFolderView(model: model, root: root, path: path.isEmpty ? name : path + "/" + name, onStarted: onStarted)
                                } label: { StartRow(title: name, symbol: "folder") }.buttonStyle(.plain)
                            }
                            if listing.truncated { Text(String(localized: "start.truncated")).font(.footnote).foregroundStyle(.secondary) }
                        } else if let listingError { Text(listingError).font(.footnote).foregroundStyle(.red) }
                        else { ProgressView().frame(maxWidth: .infinity) }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(MobileDesign.pageInset)
            }
        }
        .task { await load() }
    }
    private func load() async {
        do { listing = try await model.listing(root: root, path: path); listingError = nil }
        catch { listingError = ErrorPresentation().message(error) }
    }
    private func start(fresh: Bool) async {
        let result = await model.start(root: root, path: path, agent: model.agent, fresh: fresh)
        if result.accepted { onStarted(model.hostID, result.surfaceID) }
    }
}

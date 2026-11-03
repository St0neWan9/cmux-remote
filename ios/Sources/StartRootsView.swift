import SwiftUI
import CmuxRemoteCore

/// The project folders the Mac found in the chosen workspace.
struct StartRootsView: View {
    let model: StartSessionModel
    /// Presented first in the sheet (closes) or pushed (goes back).
    let closes: Bool
    let onStarted: (_ hostID: String, _ surfaceID: String?) -> Void
    var body: some View {
        WhitePage(title: model.workspace.title, dismissal: closes ? .close : .back) {
            ScrollView {
                VStack(alignment: .leading, spacing: MobileDesign.rowGap) {
                    Text(String(localized: "start.choose_folder")).font(.headline)
                    if model.loading && model.roots.isEmpty { ProgressView().frame(maxWidth: .infinity) }
                    else if model.roots.isEmpty && model.error == nil {
                        Text(String(localized: "start.no_folders")).font(.footnote).foregroundStyle(.secondary)
                    }
                    ForEach(model.roots) { root in
                        NavigationLink {
                            StartFolderView(model: model, root: root, path: "", onStarted: onStarted)
                        } label: {
                            StartRow(title: URL(fileURLWithPath: root.path).lastPathComponent, detail: root.path, symbol: "folder")
                        }.buttonStyle(.plain).accessibilityIdentifier("start.root." + root.id.prefix(12))
                    }
                    if let error = model.error { Text(error).font(.footnote).foregroundStyle(.red) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(MobileDesign.pageInset)
            }
            .refreshable { await model.loadRoots() }
        }
        .task { if model.roots.isEmpty { await model.loadRoots() } }
    }
}

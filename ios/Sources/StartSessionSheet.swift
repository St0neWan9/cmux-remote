import SwiftUI
import CmuxRemoteCore

/// New session: choose a workspace (unless one was chosen from its group), then a folder and an agent.
struct StartSessionSheet: View {
    let targets: [StartTarget]
    let multipleMacs: Bool
    /// Called after cmux confirmed the terminal; the surface is nil when an earlier receipt was replayed.
    let onStarted: (_ hostID: String, _ surfaceID: String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: StartSessionModel?
    /// Held for the sheet's lifetime so folder choices survive view updates.
    @State private var preselected: StartSessionModel?

    init(targets: [StartTarget], preselected: StartTarget?, multipleMacs: Bool, onStarted: @escaping (_ hostID: String, _ surfaceID: String?) -> Void) {
        self.targets = targets; self.multipleMacs = multipleMacs; self.onStarted = onStarted
        _preselected = State(initialValue: preselected.map(Self.model(for:)))
    }
    var body: some View {
        AppNavigationStack {
            if let preselected {
                StartRootsView(model: preselected, closes: true, onStarted: finish)
            } else {
                WhitePage(title: String(localized: "start.title"), dismissal: .close) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: MobileDesign.rowGap) {
                            Text(String(localized: "start.choose_workspace")).font(.headline)
                            if targets.isEmpty { Text(String(localized: "start.no_workspaces")).font(.footnote).foregroundStyle(.secondary) }
                            ForEach(targets) { target in
                                Button { chosen = Self.model(for: target) } label: {
                                    StartRow(title: target.workspace.title, detail: multipleMacs ? target.hostName : nil, symbol: "macwindow")
                                }.buttonStyle(.plain).accessibilityIdentifier("start.workspace." + target.workspace.id.lowercased())
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(MobileDesign.pageInset)
                    }
                }
                .navigationDestination(item: $chosen) { model in StartRootsView(model: model, closes: false, onStarted: finish) }
            }
        }
    }
    private static func model(for target: StartTarget) -> StartSessionModel {
        StartSessionModel(hostID: target.hostID, workspace: target.workspace, client: target.client)
    }
    private func finish(hostID: String, surfaceID: String?) { dismiss(); onStarted(hostID, surfaceID) }
}

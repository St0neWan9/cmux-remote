import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient

/// The tasks the agent detached and has not finished, above the input box.
///
/// They outlive the turn that started them, so this stays visible after a turn ends — the answer can
/// arrive while a build, a monitor or a subagent is still working. One line keeps it out of the way;
/// tapping it names each task.
struct BackgroundTasksBar: View {
    let tasks: [BackgroundAgentTask]
    /// The conversation the tasks belong to; their own records are read through it.
    let sessionID: String
    let client: RemoteClient
    @State private var expanded = false
    @State private var opened: BackgroundAgentTask?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { withAnimation(.snappy(duration: 0.18)) { expanded.toggle() } } label: {
                HStack(spacing: 7) {
                    Image(systemName: "gearshape.2").font(.footnote)
                    Text(String.localizedStringWithFormat(String(localized: "chat.background.count"), tasks.count)).font(.footnote)
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.caption2)
                }.foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("chat.background")
            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(tasks) { task in
                        Button { opened = task } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 7) {
                                Text("•").font(.caption2)
                                Text(task.tool).font(.caption.weight(.medium))
                                Text(task.summary).font(.caption).lineLimit(2)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right").font(.caption2)
                            }.foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("chat.background.task")
                    }
                }.padding(.leading, 2).accessibilityIdentifier("chat.background.list")
            }
        }.padding(.horizontal, 12)
        .sheet(item: $opened) { task in
            BackgroundTaskSheet(task: task, sessionID: sessionID, client: client)
        }
    }
}

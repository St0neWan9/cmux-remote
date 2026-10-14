import SwiftUI
import CmuxRemoteCore

/// The tasks the agent detached and has not finished, above the input box.
///
/// They outlive the turn that started them, so this stays visible after a turn ends — the answer can
/// arrive while a build, a monitor or a subagent is still working. One line keeps it out of the way;
/// tapping it names each task.
struct BackgroundTasksBar: View {
    let tasks: [BackgroundAgentTask]
    @State private var expanded = false
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
                        HStack(alignment: .firstTextBaseline, spacing: 7) {
                            Text("•").font(.caption2)
                            Text(task.tool).font(.caption.weight(.medium))
                            Text(task.summary).font(.caption).lineLimit(2)
                        }.foregroundStyle(.secondary)
                    }
                }.padding(.leading, 2).accessibilityIdentifier("chat.background.list")
            }
        }.padding(.horizontal, 12)
    }
}

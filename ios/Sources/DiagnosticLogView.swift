import SwiftUI

struct DiagnosticLogView: View {
    @State private var entries: [DiagnosticLog.Entry] = []
    @State private var copied = false

    var body: some View {
        NavigationStack {
            List(entries.reversed()) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(entry.level.rawValue.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(levelColor(entry.level))
                        Text("[\(entry.category)]")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(entry.timestamp, style: .time)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.message)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
            }
            .listStyle(.plain)
            .navigationTitle("诊断日志")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(copied ? "已复制" : "复制全部") {
                        let formatter = ISO8601DateFormatter()
                        let text = entries.reversed().map { e in
                            "[\(formatter.string(from: e.timestamp))] [\(e.level.rawValue)] [\(e.category)] \(e.message)"
                        }.joined(separator: "\n")
                        UIPasteboard.general.string = text
                        copied = true
                        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
                    }
                    .font(.subheadline)
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("清除") {
                        Task { await DiagnosticLog.shared.clear(); await refresh() }
                    }
                    .font(.subheadline)
                }
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }

    private func refresh() async {
        entries = await DiagnosticLog.shared.all()
    }

    private func levelColor(_ level: DiagnosticLog.Level) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
}

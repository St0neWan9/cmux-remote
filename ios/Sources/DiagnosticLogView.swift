import SwiftUI

struct DiagnosticLogView: View {
    @State private var entries: [DiagnosticLog.Entry] = []
    @State private var copied = false
    /// Milliseconds tell apart a dial, its path outcomes and the requests that waited on it.
    private static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
    /// The build a report came from, shown above the entries and first in a copied report.
    private var build: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?", number = info?["CFBundleVersion"] as? String ?? "?"
        return "cmux-remote \(version) (\(number)) · iOS \(UIDevice.current.systemVersion)"
    }

    var body: some View {
        WhitePage(title: String(localized: "diagnostics.title"), dismissal: .close) {
            VStack(spacing: 0) {
                List {
                    Section {
                        ForEach(entries.reversed()) { entry in row(entry) }
                    } header: {
                        Text(build)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .listStyle(.plain)
                VStack(spacing: MobileDesign.rowGap) {
                    Button(copied ? String(localized: "diagnostics.copied") : String(localized: "diagnostics.copy")) { copy() }
                    Button(String(localized: "diagnostics.clear"), role: .destructive) {
                        Task { await DiagnosticLog.shared.clear(); await refresh() }
                    }
                }.buttonStyle(FloatingButtonStyle(fullWidth: true)).padding(MobileDesign.pageInset)
            }
            .task { await refresh() }
            .refreshable { await refresh() }
        }
    }

    private func copy() {
        let lines = entries.reversed().map { e in
            "[\(Self.time.string(from: e.timestamp))] [\(e.level.rawValue)] [\(e.category)] \(e.message)"
        }
        let day = Date().formatted(.iso8601.year().month().day())
        UIPasteboard.general.string = ([build + " · " + day] + lines).joined(separator: "\n")
        copied = true
        Task { try? await Task.sleep(for: .seconds(2)); copied = false }
    }

    private func row(_ entry: DiagnosticLog.Entry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(entry.level.rawValue.uppercased())
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(levelColor(entry.level))
                Text("[\(entry.category)]")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(Self.time.string(from: entry.timestamp))
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

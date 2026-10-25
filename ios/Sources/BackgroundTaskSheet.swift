import SwiftUI
import CmuxRemoteCore
import CmuxRemoteClient
import CmuxAgentChat

/// One background task's own record: an asynchronous Agent's conversation, or a detached command's output.
///
/// The record is read from the Mac that runs the task and grows while the task runs, so the sheet follows it
/// until it is closed. Output is paged from the beginning, as asked: the reader loads forward and appends what
/// arrives while it is at the end.
struct BackgroundTaskSheet: View {
    let task: BackgroundAgentTask
    let sessionID: String
    let client: RemoteClient
    @Environment(\.dismiss) private var dismiss
    @State private var messages: [ChatMessage] = []
    @State private var output = ""
    @State private var loadedBytes = 0
    @State private var nextOffset: Int?
    @State private var totalBytes = 0
    @State private var running = true
    @State private var failure: String?
    @State private var loading = false

    private static let pageSize = 65_536

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 7) {
                        Image(systemName: task.tool == "Agent" ? "person.2" : "terminal").font(.caption)
                        Text(task.tool).font(.caption.weight(.medium))
                        Text(task.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        Spacer(minLength: 0)
                    }.foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    if let failure {
                        Text(failure).font(.callout).foregroundStyle(.secondary)
                    } else if loading && messages.isEmpty && output.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    } else if task.tool == "Agent" || !messages.isEmpty {
                        ForEach(messages) { message in MessageRow(message: message) }
                    } else {
                        Text(output.isEmpty ? String(localized: running ? "chat.background.waiting" : "chat.background.empty") : output)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let nextOffset, nextOffset > 0 {
                            Button(String(localized: "chat.background.loadMore")) { Task { await load(from: nextOffset) } }
                                .buttonStyle(.bordered)
                                .accessibilityIdentifier("chat.background.more")
                        }
                    }
                    if running {
                        HStack(spacing: 7) {
                            ProgressView().controlSize(.mini)
                            Text(String(localized: "chat.background.running")).font(.caption)
                            Spacer()
                            if totalBytes > 0 { Text(ByteCountFormatter.string(fromByteCount: Int64(totalBytes), countStyle: .file)).font(.caption2) }
                        }.foregroundStyle(.secondary).padding(.top, 4)
                        .accessibilityIdentifier("chat.background.running")
                    }
                }.padding(.horizontal, 14).padding(.vertical, 12)
            }
            .navigationTitle(task.summary.isEmpty ? task.tool : task.summary)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button(String(localized: "page.close")) { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    if running { ProgressView().controlSize(.small) }
                }
            }
            .task {
                await load(from: 0)
                for await _ in client.changes(paths: ["/v1/sessions/\(sessionID)/tasks/\(task.id)"]) {
                    await follow()
                }
            }
        }
    }

    private func load(from offset: Int) async {
        loading = true; defer { loading = false }
        do {
            let page = try await client.get("/v1/sessions/\(sessionID)/tasks/\(task.id)",
                                            query: ["offset": String(offset), "limit": String(Self.pageSize)],
                                            as: BackgroundTaskContent.self)
            running = page.running
            if page.kind == .agent {
                messages = page.snapshot?.messages ?? []
            } else if offset == 0 {
                output = page.text ?? ""; loadedBytes = page.nextOffset ?? (page.totalBytes ?? 0)
            } else {
                output += page.text ?? ""; loadedBytes = page.nextOffset ?? (page.totalBytes ?? 0)
            }
            nextOffset = page.nextOffset; totalBytes = page.totalBytes ?? 0
            failure = nil
        } catch {
            // A record that disappeared after content arrived keeps what is on screen; only an empty sheet
            // reports the failure in place of an answer.
            let message = ErrorPresentation().message(error)
            if messages.isEmpty && output.isEmpty { failure = message } else { failure = nil }
        }
    }

    /// A change notice: read what the record gained, not the whole of it again.
    private func follow() async {
        guard !loading else { return }
        if task.tool == "Agent" || !messages.isEmpty {
            await load(from: 0)
            return
        }
        guard nextOffset == nil else { return }
        await load(from: loadedBytes)
    }
}

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
    /// Whether the Agent's conversation has earlier messages than the page on screen.
    @State private var command: String?
    @State private var hasMore = false
    @State private var loadingEarlier = false
    @State private var content: ConversationSnapshot?
    @State private var output = ""
    @State private var loadedBytes = 0
    @State private var nextOffset: Int?
    @State private var totalBytes = 0
    @State private var running = true
    @State private var failure: String?
    @State private var loading = false
    /// The stored copy is shown before the first read, as the conversation page does.
    @State private var cache = BackgroundTaskCache()
    /// Bumped when content lands, so the newest line is on screen without the reader hunting for it.
    @State private var landAtBottom = 0
    private var scope: String { client.operationRecoveryScope }

    private static let pageSize = 65_536

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
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
                        // Reaching the top loads the page before it, as the conversation page does.
                        if hasMore {
                            Group { if loadingEarlier { ProgressView().controlSize(.small) } else { Color.clear } }
                                .frame(maxWidth: .infinity).frame(height: 28)
                                .onGeometryChange(for: Bool.self) { $0.frame(in: .named("taskSheet")).minY > -240 } action: { near in
                                    if near, hasMore, !loadingEarlier { Task { await loadEarlier() } }
                                }
                                .accessibilityIdentifier("chat.background.earlier")
                        }
                        // The same rows and rhythm as the timeline's groups, so a tool item reads the same here.
                        MessageRows(messages: messages, lazy: true)
                    } else {
                        if let command {
                            VStack(alignment: .leading, spacing: 6) {
                                Label(String(localized: "chat.background.command"), systemImage: "terminal").font(.caption).foregroundStyle(.secondary)
                                Text(command).font(.system(.footnote, design: .monospaced)).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(10)
                                    .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
                            }.accessibilityIdentifier("chat.background.command")
                        }
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
                    Color.clear.frame(height: 1).id("task.bottom")
                }.padding(.horizontal, 14).padding(.vertical, 12)
            }
            .coordinateSpace(name: "taskSheet")
            .onChange(of: landAtBottom) { withAnimation(.snappy(duration: 0.18)) { proxy.scrollTo("task.bottom", anchor: .bottom) } }
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
                await restore()
                await load(from: 0)
                for await _ in client.changes(paths: ["/v1/sessions/\(sessionID)/tasks/\(task.id)"]) {
                    await follow()
                }
            }
        }
    }

    /// Shows what was read last, so reopening the sheet is never blank, then the read below confirms it.
    private func restore() async {
        guard let entry = await cache.load(scope: scope, sessionID: sessionID, taskID: task.id) else { return }
        messages = entry.snapshot?.messages ?? []
        output = entry.text ?? ""
        loadedBytes = entry.loadedBytes
        totalBytes = entry.totalBytes
        running = entry.running
        nextOffset = entry.nextOffset
        command = entry.command
        landAtBottom += 1
    }
    private func save() {
        let entry = BackgroundTaskCache.Entry(snapshot: content, command: command, text: output, loadedBytes: loadedBytes,
                                              nextOffset: nextOffset, totalBytes: totalBytes, running: running, storedAt: Date())
        let scope = scope, sessionID = sessionID, taskID = task.id
        Task { await cache.save(entry, scope: scope, sessionID: sessionID, taskID: taskID) }
    }
    private func load(from offset: Int) async {
        loading = true; defer { loading = false }
        do {
            let page = try await client.get("/v1/sessions/\(sessionID)/tasks/\(task.id)",
                                            query: ["offset": String(offset), "limit": String(Self.pageSize)],
                                            as: BackgroundTaskContent.self)
            running = page.running
            if page.kind == .agent {
                content = page.snapshot
                messages = page.snapshot?.messages ?? []
                hasMore = page.snapshot?.hasMore ?? false
            } else if offset == 0 {
                output = page.text ?? ""; loadedBytes = page.nextOffset ?? (page.totalBytes ?? 0)
            } else {
                output += page.text ?? ""; loadedBytes = page.nextOffset ?? (page.totalBytes ?? 0)
            }
            nextOffset = page.nextOffset; totalBytes = page.totalBytes ?? 0
            if let sent = page.command { command = sent }
            failure = nil
            save()
            landAtBottom += 1
        } catch {
            // A record that disappeared after content arrived keeps what is on screen; only an empty sheet
            // reports the failure in place of an answer.
            let message = ErrorPresentation().message(error)
            if messages.isEmpty && output.isEmpty { failure = message } else { failure = nil }
            // A record the Mac no longer has cannot be running here; stop showing progress for it.
            if (error as? BridgeError)?.code == "task_unavailable" { running = false }
        }
    }

    /// The page before the oldest message on screen, so a long Agent conversation can be read from its start.
    private func loadEarlier() async {
        guard let first = messages.first else { return }
        loadingEarlier = true; defer { loadingEarlier = false }
        do {
            let page = try await client.get("/v1/sessions/\(sessionID)/tasks/\(task.id)",
                                            query: ["offset": "0", "limit": String(Self.pageSize), "before_seq": String(first.seq)],
                                            as: BackgroundTaskContent.self)
            guard let earlier = page.snapshot else { return }
            messages = earlier.messages + messages
            hasMore = earlier.hasMore
            failure = nil
        } catch {
            failure = (error as? BridgeError)?.message ?? ErrorPresentation().message(error)
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

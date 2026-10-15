import Foundation
import CmuxRemoteCore
import CmuxRemoteClient
import CmuxAgentChat

/// Conversations running off screen are read in the foreground, so switching to one shows its latest messages.
struct RunningSyncChecks {
    @MainActor final class Reads { var count: [String: Int] = [:]; var made: [String] = [] }

    @MainActor static func run() async -> (count: Int, failures: [String]) {
        var failures: [String] = []; var count = 0
        func check(_ condition: Bool, _ description: String) { count += 1; if !condition { failures.append(description) } }
        let client = RemoteClient(pairing: try! PairingConfiguration(host: "localhost", port: 1, token: String(repeating: "0", count: 32), certificateSHA256: String(repeating: "0", count: 64)))
        let reads = Reads()
        var models: [String: ConversationModel] = [:]
        func model(_ id: String) -> ConversationModel {
            if let existing = models[id] { return existing }
            reads.made.append(id)
            let descriptor = SessionDescriptor(id: id, agent: "claude", title: id, cwd: nil, state: "working")
            let made = ConversationModel(session: descriptor, client: client, loadRecovery: { nil }, saveRecovery: { _ in },
                readSessions: { [descriptor] },
                readHistory: { _ in
                    await MainActor.run { reads.count[id, default: 0] += 1 }
                    return ConversationSnapshot(messages: [ChatMessage(id: id + "-latest", seq: 1, role: .agent, timestamp: .distantPast, kind: .prose(ChatProse(text: "latest")))], hasMore: false, generation: "g", clipped: false)
                },
                readPreview: { PreviewSnapshot(text: nil, available: false) })
            models[id] = made; return made
        }
        func target(_ id: String, running: Bool) -> RunningSessionSync.Target {
            RunningSessionSync.Target(key: id, running: running, model: { model(id) })
        }
        func settle() async { for _ in 0..<40 { await Task.yield() }; try? await Task.sleep(for: .milliseconds(50)) }

        let sync = RunningSessionSync(limit: 3, interval: .seconds(60))
        sync.update([target("a", running: true), target("idle", running: false), target("b", running: true),
                     target("c", running: true), target("d", running: true), target("e", running: true)])
        await settle()
        check(sync.followed == ["a", "b", "c"], "More conversations were followed than the limit, or not the most recent")
        check(!reads.made.contains("idle"), "A conversation that is not running was loaded")
        check(!reads.made.contains("d") && !reads.made.contains("e"), "A conversation past the limit was loaded")
        check(reads.count["a"] == 1 && models["a"]?.messages.map(\.id) == ["a-latest"], "A conversation running off screen was not read")

        // One on screen follows its own changes; the off-screen follower does not read it a second time.
        let shown = model("b")
        let observer = Task { await shown.observeChanges() }
        await settle()
        let before = reads.count["b"] ?? 0
        await shown.syncHidden()
        check(reads.count["b"] == before, "A conversation on screen was also read by the off-screen follower")
        // On screen it is not followed a second time: its own observer holds the subscription.
        check(!shown.following && !sync.followed.contains("b"), "A conversation on screen was also followed off screen")
        observer.cancel(); await settle()
        sync.update([target("a", running: true), target("b", running: true), target("c", running: true)])
        check(shown.following, "A conversation that left the screen was not followed again")

        // A turn that stops off screen is read once more, so its final answer is there; then it is no longer followed.
        let finishedBefore = reads.count["a"] ?? 0
        sync.update([target("a", running: false), target("c", running: true)])
        await settle()
        check(reads.count["a"] == finishedBefore + 1, "A conversation that just finished was not read for its final answer")
        check(sync.followed == ["c"], "A finished conversation was still followed")

        sync.stop()
        check(sync.followed.isEmpty, "Followers outlived the foreground")

        // A background wake reads what is running or changed since stored, within the same limit, and follows nothing.
        let wake = RunningSessionSync(limit: 2, interval: .seconds(60))
        var changed = target("changed", running: false); changed.changedSinceStored = true
        let read = await wake.pass([target("quiet", running: false), changed, target("live", running: true), target("extra", running: true)])
        check(read == 2 && reads.count["changed"] == 1 && reads.count["live"] == 1, "A background wake did not read what changed and what runs")
        check(!reads.made.contains("quiet") && !reads.made.contains("extra"), "A background wake read past its selection or limit")
        check(wake.followed.isEmpty, "A background wake left a follower running")
        return (count, failures)
    }
}

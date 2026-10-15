import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteClient

@Suite struct PathWatchHubTests {
    actor Probe {
        var started: [String] = []
        var cancelled: [String] = []
        var changes: [String: @Sendable () async -> Void] = [:]
        func start(_ path: String, _ changed: @escaping @Sendable () async -> Void) { started.append(path); changes[path] = changed }
        func cancel(_ path: String) { cancelled.append(path) }
        func fire(_ path: String) async { await changes[path]?() }
    }
    actor Counter { var value = 0; var finished = false; func add() { value += 1 }; func finish() { finished = true } }

    /// `refused` paths end as soon as they start, like a subscription the Bridge refuses for good.
    private func hub(_ probe: Probe, refused: Set<String> = []) -> PathWatchHub {
        PathWatchHub { path, changed in
            await probe.start(path, changed)
            if refused.contains(path) { return }
            while !Task.isCancelled { try? await Task.sleep(for: .milliseconds(10)) }
            await probe.cancel(path)
        }
    }
    private func settle() async { try? await Task.sleep(for: .milliseconds(80)) }

    /// Pages and followers watching the same path share one subscription, and each of them hears its changes.
    @Test func watchersOfOnePathShareOneSubscription() async {
        let probe = Probe(), hub = hub(probe)
        let counters = [Counter(), Counter(), Counter()]
        let ids = counters.map { _ in UUID() }
        for (id, counter) in zip(ids, counters) {
            await hub.add(id, paths: ["/v1/sessions/a/preview"], changed: { Task { await counter.add() } }, finished: {})
        }
        await settle()
        #expect(await probe.started == ["/v1/sessions/a/preview"])
        #expect(await hub.subscribedPaths == 1)
        // The two that joined an existing subscription were told to read at once.
        let joined = (await counters[1].value, await counters[2].value)
        #expect(joined == (1, 1))
        await probe.fire("/v1/sessions/a/preview"); await settle()
        let heard = [await counters[0].value, await counters[1].value, await counters[2].value]
        #expect(heard == [1, 2, 2])
        // The subscription stays while anyone watches, and ends with the last of them.
        await hub.remove(ids[0]); await hub.remove(ids[1]); await settle()
        #expect(await probe.cancelled.isEmpty)
        await hub.remove(ids[2]); await settle()
        #expect(await probe.cancelled == ["/v1/sessions/a/preview"])
        #expect(await hub.subscribedPaths == 0)
    }

    /// A subscription refused for good finishes the watchers that had nothing else to watch.
    @Test func aRefusedSubscriptionFinishesItsWatchers() async {
        let probe = Probe(), hub = hub(probe, refused: ["/v1/feed"])
        let alone = Counter(), shared = Counter()
        await hub.add(UUID(), paths: ["/v1/feed"], changed: {}, finished: { Task { await alone.finish() } })
        await hub.add(UUID(), paths: ["/v1/feed", "/v1/sessions"], changed: {}, finished: { Task { await shared.finish() } })
        await settle()
        #expect(await alone.finished)
        #expect(await !shared.finished)
    }

    /// Nine watchers of three paths on one link stay within its eight subscriptions.
    @Test(.timeLimit(.minutes(1))) func duplicateWatchersDoNotFillTheLink() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let lines = Lines()
        let client = try RemoteClient(connection: fixture.connection, trace: { line in Task { await lines.append(line) } })
        do {
            let paths = ["/v1/sessions", "/v1/sessions/demo-session/history", "/v1/sessions/demo-session/preview"]
            let streams = (0..<3).map { _ in client.changes(paths: paths) }
            for stream in streams { var events = stream.makeAsyncIterator(); _ = await events.next() }
            try await Task.sleep(for: .seconds(1))
            let refused = await lines.all.filter { $0.contains("subscription ended") }
            #expect(refused.isEmpty, "Subscriptions ended: \(refused)")
            _ = streams
            client.close(); await fixture.stop()
        } catch { client.close(); await fixture.stop(); throw error }
    }
    actor Lines { var all: [String] = []; func append(_ line: String) { all.append(line) } }
}

import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

@Suite struct EventMonitorTests {
    func ack(_ boot: String, latest: Int, gap: Bool = false) -> JSONValue {
        .object(["type": .string("ack"), "boot_id": .string(boot), "resume": .object(["latest_seq": .number(Double(latest)), "gap": .bool(gap)])])
    }
    func event(_ boot: String, seq: Int) -> JSONValue {
        .object(["type": .string("event"), "boot_id": .string(boot), "seq": .number(Double(seq)), "category": .string("agent")])
    }
    func monitor(_ repository: CmuxEventCursorRepository, fixture: EventMonitorFixture) -> CmuxEventMonitor {
        .init(repository: repository, consume: { after, receive in try await fixture.consume(after: after, receive: receive) },
            invalidate: { await fixture.invalidate() }, refresh: { await fixture.refresh() }, accept: { await fixture.accept($0) }, wait: { try await fixture.wait($0) })
    }
    @Test func disconnectBootChangeAndRestartUseOnlyTheirOwnCursorNamespace() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CmuxEventCursorRepository(directory: directory)
        try await repository.save(.init(bootID: "boot-a", sequence: 10))
        let fixture = EventMonitorFixture(stages: [[ack("boot-a", latest: 12), event("boot-a", seq: 10), event("boot-a", seq: 12)],
            [ack("boot-b", latest: 5)], [ack("boot-b", latest: 5), event("boot-b", seq: 6)]])
        await monitor(repository, fixture: fixture).run()
        #expect(await fixture.attempts == [10, 12, nil])
        #expect(await fixture.accepted.filter { $0["type"].string == "event" }.map { $0["seq"].int! } == [12, 6])
        #expect(await fixture.refreshes == 4); #expect(await fixture.resets >= 6)
        #expect(try await repository.load() == .init(bootID: "boot-b", sequence: 6))
        let resumed = EventMonitorFixture(stages: [[ack("boot-b", latest: 6), event("boot-b", seq: 7)]])
        await monitor(CmuxEventCursorRepository(directory: directory), fixture: resumed).run()
        #expect(await resumed.attempts == [6])
        #expect(try await repository.load()?.sequence == 7)
        let attrs = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("cmux-event-cursor.json").path)
        #expect((attrs[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    }
    @Test func replayGapRefreshesSnapshotAndReconnectsWithoutOldSequence() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CmuxEventCursorRepository(directory: directory)
        try await repository.save(.init(bootID: "boot-a", sequence: 1))
        let fixture = EventMonitorFixture(stages: [[ack("boot-a", latest: 100, gap: true)], [ack("boot-a", latest: 100), event("boot-a", seq: 102)]])
        await monitor(repository, fixture: fixture).run()
        #expect(await fixture.attempts == [1, nil])
        #expect(await fixture.refreshes == 3)
        #expect(try await repository.load()?.sequence == 102)
    }
    @Test(.timeLimit(.minutes(1))) func realSocketReconnectReplaysAndPersistsTheIndependentCursor() async throws {
        let directory = URL(fileURLWithPath: "/tmp/cmux-event-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let repository = CmuxEventCursorRepository(directory: directory)
        try await repository.save(.init(bootID: "boot-a", sequence: 3))
        let fixture = WireEventFixture(path: directory.appendingPathComponent("events.sock").path,
            stages: [[ack("boot-a", latest: 4), event("boot-a", seq: 4)],
                [ack("boot-b", latest: 9, gap: true)], [ack("boot-b", latest: 9), event("boot-b", seq: 10)]])
        let monitor = CmuxEventMonitor(repository: repository,
            consume: { after, receive in try await fixture.consume(after: after, receive: receive) },
            invalidate: { await fixture.invalidate() }, refresh: { await fixture.refresh() },
            accept: { await fixture.accept($0) }, wait: { try await fixture.wait($0) })
        await monitor.run()
        #expect(await fixture.subscriptions.map { $0["params"]["after_seq"] } == [.number(3), .number(4), .null])
        #expect(await fixture.subscriptions.allSatisfy { $0["method"].string == "events.stream" })
        #expect(await fixture.accepted.filter { $0["type"].string == "event" }.map { $0["seq"].int } == [4, 10])
        #expect(await fixture.invalidations >= 4)
        #expect(try await repository.load() == .init(bootID: "boot-b", sequence: 10))
        let resumed = WireEventFixture(path: directory.appendingPathComponent("resume.sock").path,
            stages: [[ack("boot-b", latest: 10), event("boot-b", seq: 11)]])
        await CmuxEventMonitor(repository: CmuxEventCursorRepository(directory: directory),
            consume: { after, receive in try await resumed.consume(after: after, receive: receive) },
            invalidate: { await resumed.invalidate() }, refresh: { await resumed.refresh() },
            accept: { await resumed.accept($0) }, wait: { try await resumed.wait($0) }).run()
        #expect(await resumed.subscriptions.first?["params"]["after_seq"] == .number(10))
        #expect(try await repository.load()?.sequence == 11)
    }
    @Test(.timeLimit(.minutes(1))) func cancellationStopsStreamAndInvalidatesBindings() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let ready = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let fixture = EventMonitorFixture(stages: [])
        let monitor = CmuxEventMonitor(repository: .init(directory: directory), consume: { _, _ in
            ready.continuation.yield(()); try await Task.sleep(for: .seconds(60))
        }, invalidate: { await fixture.invalidate() }, refresh: { await fixture.refresh() }, accept: { await fixture.accept($0) })
        let job = Task { await monitor.run() }
        var started = ready.stream.makeAsyncIterator(); _ = await started.next()
        job.cancel(); await job.value
        #expect(await fixture.resets == 2)
        #expect(await fixture.refreshes == 1)
    }
}

import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge
@testable import CmuxRemoteMac

/// An owner socket the test opens once the resident is expected to be up.
private actor ControllableOwner: CmuxControlling {
    private var available = false
    /// The resident answers only while its own child is alive, as a real owner socket does.
    var living: @Sendable () -> Bool = { true }
    /// The owner-protocol revision the fake resident reports through `bridge.status`.
    private var revision = OwnerRevision.current
    func open(_ living: @escaping @Sendable () -> Bool) { available = true; self.living = living }
    func setRevision(_ newRevision: Int) { revision = newRevision }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        guard available, living() else { throw BridgeError("unavailable", "No resident is listening", status: 503) }
        if method == "bridge.status" { return .object(["owner_revision": .number(Double(revision))]) }
        return .object(["pong": .bool(true)])
    }
}

/// A child the test stops on demand, standing in for a resident that crashes.
private final class FakeProcess: RunningProcess, @unchecked Sendable {
    private let lock = NSLock()
    private var exitWaiters: [CheckedContinuation<Void, Never>] = []
    private var running = true
    var isRunning: Bool { lock.withLock { running } }
    func terminate() { exit() }
    func exit() {
        lock.lock(); running = false; let waiters = exitWaiters; exitWaiters = []; lock.unlock()
        for waiter in waiters { waiter.resume() }
    }
    func waitForExit() async {
        // A child that already exited must not leave the supervisor waiting for an event that has passed.
        if !isRunning { return }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            lock.lock()
            if running { exitWaiters.append(done); lock.unlock() } else { lock.unlock(); done.resume() }
        }
    }
}

@Suite struct MacResidentSupervisionTests {
    private func fixture(stopStale: (@Sendable () async throws -> Void)? = nil) throws -> (MacResidentLauncher, ControllableOwner, Children) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("resident-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // A completed, private setup is what tells the launcher that restarting is worth trying.
        let setup = try JSONSerialization.data(withJSONObject: ["CMUX_SOCKET_PATH": "/example/cmux.sock", "CMUX_SOCKET_CAPABILITY": "capability"])
        let setupFile = directory.appendingPathComponent("cmux-setup.json")
        try setup.write(to: setupFile)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: setupFile.path)
        let executable = directory.appendingPathComponent("cmux-remote")
        try Data("#!/bin/sh\n".utf8).write(to: executable)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        let owner = ControllableOwner(); let children = Children()
        let launcher: MacResidentLauncher
        if let stopStale {
            launcher = MacResidentLauncher(executable: executable, directory: directory, owner: owner,
                                           spawn: { _, _ in let child = FakeProcess(); children.add(child); return child },
                                           stopStale: stopStale)
        } else {
            launcher = MacResidentLauncher(executable: executable, directory: directory, owner: owner,
                                           spawn: { _, _ in let child = FakeProcess(); children.add(child); return child })
        }
        return (launcher, owner, children)
    }
    @Test(.timeLimit(.minutes(1))) func aResidentThatExitsIsReplacedAndTheAppReattaches() async throws {
        let (launcher, owner, children) = try fixture()
        let reattachments = Counter()
        let supervision = Task { await launcher.supervise { reattachments.increment() } }
        while children.count < 1 { try await Task.sleep(for: .milliseconds(5)) }
        await owner.open { children.latest?.isRunning == true }
        // The resident answers its socket, so the launcher waits on the process rather than on startup.
        while !(await launcher.isWaitingForExitForTesting) { try await Task.sleep(for: .milliseconds(5)) }
        // The heartbeat crash: the child dies while the app sits idle.
        children.first?.exit()
        // The supervisor reports the reattachment before it launches the replacement, so wait for both.
        while reattachments.value == 0 || children.count < 2 { try await Task.sleep(for: .milliseconds(10)) }
        #expect(children.count == 2)
        #expect(reattachments.value == 1)
        supervision.cancel()
    }
    @Test(.timeLimit(.minutes(1))) func aResidentThatKeepsDyingIsNotRestartedForever() async throws {
        let (launcher, owner, children) = try fixture()
        let supervision = Task { await launcher.supervise() }
        while children.count < 1 { try await Task.sleep(for: .milliseconds(5)) }
        await owner.open { children.latest?.isRunning == true }
        // Every child dies at once; the supervisor must give up rather than launch one for good.
        while !Task.isCancelled, await launcher.isSupervisingForTesting {
            children.first(where: { $0.isRunning })?.exit()
            try await Task.sleep(for: .milliseconds(20))
        }
        await supervision.value
        #expect(children.count <= 6)
        #expect(!supervision.isCancelled)
    }
    @Test(.timeLimit(.minutes(1))) func aStaleOwnerIsStoppedAndReplacedByTheBundledResident() async throws {
        let stops = Counter()
        let (launcher, owner, children) = try fixture(stopStale: { stops.increment() })
        // The adopted resident predates the bundled owner revision and answers regardless of any child.
        await owner.setRevision(0)
        await owner.open { true }
        let supervision = Task { await launcher.supervise() }
        while children.count < 1 || stops.value < 1 { try await Task.sleep(for: .milliseconds(5)) }
        #expect(stops.value == 1)
        // The replacement answers the current revision, so the launcher waits on it instead of replacing it again.
        await owner.setRevision(OwnerRevision.current)
        while !(await launcher.isWaitingForExitForTesting) { try await Task.sleep(for: .milliseconds(5)) }
        #expect(children.count == 1)
        #expect(stops.value == 1)
        supervision.cancel()
    }
    @Test func aCurrentOwnerIsAdoptedWithoutStoppingOrSpawning() async throws {
        let stops = Counter()
        let (launcher, owner, children) = try fixture(stopStale: { stops.increment() })
        await owner.open { true }
        try await launcher.ensureStarted()
        #expect(children.count == 0)
        #expect(stops.value == 0)
    }
}

/// A counter the supervising task and the test both touch.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}

/// Children handed out by the fake spawner, kept so the test can stop them.
private final class Children: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [FakeProcess] = []
    func add(_ child: FakeProcess) { lock.withLock { items.append(child) } }
    var count: Int { lock.withLock { items.count } }
    var first: FakeProcess? { lock.withLock { items.first } }
    var latest: FakeProcess? { lock.withLock { items.last } }
    func first(where predicate: (FakeProcess) -> Bool) -> FakeProcess? { lock.withLock { items.first(where: predicate) } }
}

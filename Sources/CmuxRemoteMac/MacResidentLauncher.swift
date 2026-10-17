import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Launches only the bundled resident, adopting a current owner instead of replacing it, and replaces it if it dies.
public actor MacResidentLauncher {
    /// How a supervised resident stops being supervised: a resident that dies at once, over and over, is not restarted forever.
    private static let restartsBeforeGivingUp = 5
    private static let restartWindow: Duration = .seconds(60)
    private let executable: URL
    private let directory: URL
    private let owner: any CmuxControlling
    private let spawn: @Sendable (URL, [String]) throws -> any RunningProcess
    /// Stops a running resident this launcher never spawned, so an upgraded bundled helper can replace it.
    private let stopStale: @Sendable () async throws -> Void
    private var process: (any RunningProcess)?
    private var restartTimes: [Date] = []
    private var supervising = false
    private var waitingForExit = false
    /// Whether the supervisor is still watching, for tests that must not guess how many launches to expect.
    public var isSupervisingForTesting: Bool { supervising }
    /// Whether the supervisor is waiting on the running child, so a test knows the startup phase is over.
    public var isWaitingForExitForTesting: Bool { waitingForExit }
    public init(executable: URL, directory: URL, owner: any CmuxControlling) {
        self.init(executable: executable, directory: directory, owner: owner,
            spawn: { url, arguments in try SystemProcess(url: url, arguments: arguments) },
            stopStale: { try await MacStaleResidentStopper(executable: executable, directory: directory).stop() })
    }
    init(executable: URL, directory: URL, owner: any CmuxControlling,
         spawn: @escaping @Sendable (URL, [String]) throws -> any RunningProcess,
         stopStale: @escaping @Sendable () async throws -> Void = {}) {
        self.executable = executable; self.directory = directory; self.owner = owner
        self.spawn = spawn; self.stopStale = stopStale
    }
    public func ensureStarted() async throws {
        let availability = await ownerAvailability()
        guard availability != .current else { return }
        if process?.isRunning == true {
            // A child this launcher started is still coming up; only a stale owner justifies replacing it.
            guard availability == .stale else { throw BridgeError("resident_starting", "The resident service is starting.") }
            // Its revision cannot serve the bundled companion, so it is stopped through its handle.
            if let child = process { child.terminate(); await child.waitForExit() }
            process = nil
        } else if availability == .stale {
            // An adopted resident this launcher never spawned is stopped by its exact command line.
            try await stopStale()
        }
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("cmux-setup.json").path) {
            _ = try MacSetupRepository(directory: directory).environment()
        } else if try TuiSocketDiscovery().sockets().isEmpty {
            throw BridgeError("setup_required", "Connect this app to cmux first.")
        }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw BridgeError("resident_missing", "Reinstall cmux Remote to restore its bundled service.") }
        // An adopted or freshly stopped resident that predates the bundled owner revision cannot
        // answer the newest owner methods; its sockets and mirrors move to the replacement when
        // the replacement restores them.
        let child = try spawn(executable, ["resident", "--state", directory.path])
        process = child
        // Bounded startup observation, not a fixed sleep before assuming readiness.
        for _ in 0..<30 {
            try Task.checkCancellation()
            if await ownerAvailability() == .current { return }
            guard child.isRunning else { process = nil; throw BridgeError("resident_failed", "The resident service could not start.") }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw BridgeError("resident_starting", "The resident service is still starting. Refresh its status.")
    }
    /// Watches the resident for as long as the task lives, replacing it when it exits.
    ///
    /// A resident that crashed while the app was idle used to leave the phone with no Bridge at all until the
    /// person reopened a window, so the launcher keeps the service up on its own.
    public func supervise(afterRestart: @escaping @Sendable () async -> Void = {}) async {
        supervising = true
        defer { supervising = false }
        while !Task.isCancelled {
            do { try await ensureStarted() }
            catch {
                // A missing setup or a missing executable is not something a restart can fix.
                guard await shouldKeepTryingAfterFailure() else { return }
                if await waitForRestartSlot() == false { return }
                continue
            }
            guard let running = process else { return }
            waitingForExit = true
            defer { waitingForExit = false }
            // Wait for the exit instead of polling: the process reports it, and the app stays idle otherwise.
            await running.waitForExit()
            process = nil
            guard !Task.isCancelled else { return }
            if await waitForRestartSlot() == false { return }
            // The new resident publishes a fresh owner socket, so its readers have to attach again.
            await afterRestart()
        }
    }
    /// Whether a restart is worth trying; a setup that was never completed needs the person, not another launch.
    private func shouldKeepTryingAfterFailure() async -> Bool {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("cmux-setup.json").path) { return true }
        return (try? TuiSocketDiscovery().sockets().isEmpty) == false
    }
    /// Refuses a restart loop: too many exits inside the window mean the resident is not going to stay up.
    private func waitForRestartSlot() async -> Bool {
        let now = Date()
        restartTimes = restartTimes.filter { now.timeIntervalSince($0) < 60 }
        guard restartTimes.count < Self.restartsBeforeGivingUp else { return false }
        restartTimes.append(now)
        // A short pause keeps a crash loop from spinning the CPU.
        try? await Task.sleep(for: .seconds(1))
        return !Task.isCancelled
    }
    /// Whether the owner socket serves the revision this bundled companion requires.
    private func ownerAvailability() async -> OwnerAvailability {
        guard let status = try? await owner.request("bridge.status", params: [:]) else {
            // A resident too old for `bridge.status` is replaced like any other stale one.
            if (try? await owner.request("mac.connections", params: [:])) != nil { return .stale }
            return .absent
        }
        return status["owner_revision"].int == OwnerRevision.current ? .current : .stale
    }
    private enum OwnerAvailability { case current, stale, absent }
}

/// A launched process, kept behind a protocol so supervision can be exercised without a real child.
public protocol RunningProcess: Sendable {
    var isRunning: Bool { get }
    /// Asks the child to exit, the way a supervisor stops a resident it owns.
    func terminate()
    func waitForExit() async
}

/// The bundled resident launched as a child of this app.
private final class SystemProcess: RunningProcess, @unchecked Sendable {
    private let process = Process()
    private let exited: AsyncStream<Void>.Continuation
    private let exits: AsyncStream<Void>
    init(url: URL, arguments: [String]) throws {
        process.executableURL = url; process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        (exits, exited) = AsyncStream<Void>.makeStream()
        process.terminationHandler = { [exited] _ in exited.finish() }
        try process.run()
    }
    var isRunning: Bool { process.isRunning }
    func terminate() { if process.isRunning { process.terminate() } }
    func waitForExit() async {
        if !process.isRunning { return }
        for await _ in exits { return }
    }
}

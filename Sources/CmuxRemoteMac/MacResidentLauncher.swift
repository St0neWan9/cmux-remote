import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Launches only the bundled resident, adopting an existing owner instead of replacing it, and replaces it if it dies.
public actor MacResidentLauncher {
    /// How a supervised resident stops being supervised: a resident that dies at once, over and over, is not restarted forever.
    private static let restartsBeforeGivingUp = 5
    private static let restartWindow: Duration = .seconds(60)
    private let executable: URL
    private let directory: URL
    private let owner: any CmuxControlling
    private let spawn: @Sendable (URL, [String]) throws -> any RunningProcess
    private var process: (any RunningProcess)?
    private var restartTimes: [Date] = []
    private var supervising = false
    private var waitingForExit = false
    /// Whether the supervisor is still watching, for tests that must not guess how many launches to expect.
    public var isSupervisingForTesting: Bool { supervising }
    /// Whether the supervisor is waiting on the running child, so a test knows the startup phase is over.
    public var isWaitingForExitForTesting: Bool { waitingForExit }
    public init(executable: URL, directory: URL, owner: any CmuxControlling) {
        self.init(executable: executable, directory: directory, owner: owner, spawn: { url, arguments in try SystemProcess(url: url, arguments: arguments) })
    }
    init(executable: URL, directory: URL, owner: any CmuxControlling, spawn: @escaping @Sendable (URL, [String]) throws -> any RunningProcess) {
        self.executable = executable; self.directory = directory; self.owner = owner; self.spawn = spawn
    }
    public func ensureStarted() async throws {
        if await ownerAvailable() { return }
        guard process?.isRunning != true else { throw BridgeError("resident_starting", "The resident service is starting.") }
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("cmux-setup.json").path) {
            _ = try MacSetupRepository(directory: directory).environment()
        } else if try TuiSocketDiscovery().sockets().isEmpty {
            throw BridgeError("setup_required", "Connect this app to cmux first.")
        }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw BridgeError("resident_missing", "Reinstall cmux Remote to restore its bundled service.") }
        let child = try spawn(executable, ["resident", "--state", directory.path])
        process = child
        // Bounded startup observation, not a fixed sleep before assuming readiness.
        for _ in 0..<30 {
            try Task.checkCancellation()
            if await ownerAvailable() { return }
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
    private func ownerAvailable() async -> Bool {
        if (try? await owner.request("bridge.status", params: [:])) != nil { return true }
        return (try? await owner.request("mac.connections", params: [:])) != nil
    }
}

/// A launched process, kept behind a protocol so supervision can be exercised without a real child.
public protocol RunningProcess: Sendable {
    var isRunning: Bool { get }
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
    func waitForExit() async {
        if !process.isRunning { return }
        for await _ in exits { return }
    }
}

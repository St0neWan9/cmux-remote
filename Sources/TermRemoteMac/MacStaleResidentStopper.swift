import Foundation
import Darwin
import TermRemoteBridge

/// Terminates a resident of this exact state directory that this launcher did not spawn.
///
/// A resident predating the owner revision cannot be asked over its socket to exit, so the
/// upgraded companion finds it by its exact command line, stops it, and waits for the state
/// lease to free before the replacement starts. Only the bundled resident's exact argument
/// list matches, so the cmux app itself is never touched.
struct MacStaleResidentStopper: Sendable {
    /// The helper paths a resident of this app has shipped under: the current name and the CmuxRemote one.
    static let bundledHelpers = ["/Contents/Helpers/term-remote", "/Contents/Helpers/cmux-remote"]
    private let directory: URL
    private let helpers: [String]
    /// Bounded: SIGTERM, wait for the lease, then SIGKILL rather than wait forever.
    private let grace: Duration

    init(directory: URL, helpers: [String] = Self.bundledHelpers, grace: Duration = .seconds(5)) {
        self.directory = directory; self.helpers = helpers; self.grace = grace
    }

    /// The resident the CmuxRemote app left running for its own state directory.
    ///
    /// Quitting the app never stops its resident, so after the rename the old one keeps the
    /// sharing port and the new resident cannot listen. Only the default Term Remote directory
    /// has a predecessor; a custom `--state` path is never matched to anything else.
    static func legacy(of directory: URL) -> MacStaleResidentStopper? {
        guard directory.lastPathComponent == "term-remote" else { return nil }
        let legacy = directory.deletingLastPathComponent().appendingPathComponent("cmux-remote", isDirectory: true)
        guard FileManager.default.fileExists(atPath: legacy.path) else { return nil }
        return MacStaleResidentStopper(directory: legacy, helpers: ["/Contents/Helpers/cmux-remote"])
    }

    /// Returns whether a matching resident was running and has been stopped.
    @discardableResult func stop() async throws -> Bool {
        let running = residentProcessIDs()
        guard !running.isEmpty else { return false }
        for pid in running { kill(pid, SIGTERM) }
        try await waitForLease()
        for pid in residentProcessIDs() { kill(pid, SIGKILL) }
        try await waitForLease()
        return true
    }

    /// Whether a `ps` command line is one of these helpers in resident mode for this exact state directory.
    func matches(command: Substring) -> Bool {
        let suffix = " resident --state " + directory.path
        return helpers.contains { command.hasSuffix($0 + suffix) }
    }

    /// Processes whose full command line is exactly a bundled helper in resident mode for this state directory.
    private func residentProcessIDs() -> [pid_t] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/ps")
        process.arguments = ["-axww", "-o", "pid=,command="]
        let pipe = Pipe()
        process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return [] }
        return String(decoding: data, as: UTF8.self).split(separator: "\n").compactMap { line in
            let fields = line.split(maxSplits: 1, omittingEmptySubsequences: true) { $0 == " " }
            guard fields.count == 2, matches(command: fields[1]), let pid = pid_t(fields[0]) else { return nil }
            return pid
        }
    }

    /// The replacement cannot start while the old resident holds the state lease; the lease
    /// frees the moment the process exits, so polling its acquisition is the readiness signal.
    private func waitForLease() async throws {
        let deadline = ContinuousClock.now + grace
        while ContinuousClock.now < deadline {
            if (try? BridgeRunLease(directory: directory)) != nil { return }
            try await Task.sleep(for: .milliseconds(100))
        }
    }
}

import Foundation
import Darwin
import CmuxRemoteBridge

/// Terminates a resident of this exact state directory that this launcher did not spawn.
///
/// A resident predating the owner revision cannot be asked over its socket to exit, so the
/// upgraded companion finds it by its exact command line, stops it, and waits for the state
/// lease to free before the replacement starts. Only the bundled resident's exact argument
/// list matches, so the cmux app itself is never touched.
struct MacStaleResidentStopper: Sendable {
    private let executable: URL
    private let directory: URL
    /// Bounded: SIGTERM, wait for the lease, then SIGKILL rather than wait forever.
    private let grace: Duration

    init(executable: URL, directory: URL, grace: Duration = .seconds(5)) {
        self.executable = executable; self.directory = directory; self.grace = grace
    }

    func stop() async throws {
        for pid in residentProcessIDs() { kill(pid, SIGTERM) }
        try await waitForLease()
        for pid in residentProcessIDs() { kill(pid, SIGKILL) }
        try await waitForLease()
    }

    /// Processes whose full command line is exactly this executable in resident mode for this state directory.
    private func residentProcessIDs() -> [pid_t] {
        let expected = executable.path + " resident --state " + directory.path
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
            guard fields.count == 2, fields[1] == Substring(expected), let pid = pid_t(fields[0]) else { return nil }
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

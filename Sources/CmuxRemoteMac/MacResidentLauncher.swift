import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Launches only the bundled resident, adopting an existing owner instead of replacing it.
public actor MacResidentLauncher {
    private let executable: URL
    private let directory: URL
    private let owner: any CmuxControlling
    private var process: Process?
    public init(executable: URL, directory: URL, owner: any CmuxControlling) { self.executable = executable; self.directory = directory; self.owner = owner }
    public func ensureStarted() async throws {
        if (try? await owner.request("mac.connections", params: [:])) != nil { return }
        guard process?.isRunning != true else { throw BridgeError("resident_starting", "The resident service is starting.") }
        _ = try MacSetupRepository(directory: directory).environment()
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw BridgeError("resident_missing", "Reinstall cmux Remote to restore its bundled service.") }
        let child = Process(); child.executableURL = executable
        child.arguments = ["resident", "--state", directory.path]
        child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        try child.run(); process = child
        // Bounded startup observation, not a fixed sleep before assuming readiness.
        for _ in 0..<30 {
            try Task.checkCancellation()
            if (try? await owner.request("mac.connections", params: [:])) != nil { return }
            guard child.isRunning else { process = nil; throw BridgeError("resident_failed", "The resident service could not start.") }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw BridgeError("resident_starting", "The resident service is still starting. Refresh its status.")
    }
}

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
        if await ownerAvailable() { return }
        guard process?.isRunning != true else { throw BridgeError("resident_starting", "The resident service is starting.") }
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("cmux-setup.json").path) {
            _ = try MacSetupRepository(directory: directory).environment()
        } else if try TuiSocketDiscovery().sockets().isEmpty {
            throw BridgeError("setup_required", "Connect this app to cmux first.")
        }
        guard FileManager.default.isExecutableFile(atPath: executable.path) else { throw BridgeError("resident_missing", "Reinstall cmux Remote to restore its bundled service.") }
        let child = Process(); child.executableURL = executable
        child.arguments = ["resident", "--state", directory.path]
        child.standardOutput = FileHandle.nullDevice; child.standardError = FileHandle.nullDevice
        try child.run(); process = child
        // Bounded startup observation, not a fixed sleep before assuming readiness.
        for _ in 0..<30 {
            try Task.checkCancellation()
            if await ownerAvailable() { return }
            guard child.isRunning else { process = nil; throw BridgeError("resident_failed", "The resident service could not start.") }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw BridgeError("resident_starting", "The resident service is still starting. Refresh its status.")
    }
    private func ownerAvailable() async -> Bool {
        if (try? await owner.request("bridge.status", params: [:])) != nil { return true }
        return (try? await owner.request("mac.connections", params: [:])) != nil
    }
}

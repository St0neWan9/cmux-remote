import Foundation
import Observation
import CmuxRemoteMac
import CmuxRemoteBridge
import CmuxRemoteCore

/// One application lifetime owns observation; closing Settings never stops its service.
@MainActor @Observable final class MacAppModel {
    var remote: MacCompanionModel
    var sharing: MacSharingModel
    var section = "share"
    var statePath: String
    var serviceError: String?
    var starting = false
    private let executable: URL
    private let preferences: UserDefaults
    private var launcher: MacResidentLauncher
    private var startup: Task<Void, Never>?
    init(executable: URL, home: URL, preferences: UserDefaults) {
        self.executable = executable; self.preferences = preferences
        let path = preferences.string(forKey: "bridgeStatePath") ?? home.appendingPathComponent(".local/state/cmux-remote").path
        statePath = path
        let directory = URL(fileURLWithPath: path)
        let owner = UnixSocketClient(path: directory.appendingPathComponent("owner.sock").path)
        remote = MacCompanionModel(owner: owner, discovery: OwnerBridgeDiscovery(owner: owner))
        sharing = MacSharingModel(owner: owner)
        launcher = MacResidentLauncher(executable: executable, directory: directory, owner: owner)
    }
    var setupCommand: String { "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "' setup --state '" + statePath.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    func start() async {
        if let startup { await startup.value; return }
        let task = Task<Void, Never> { [weak self] in guard let self else { return }; await self.reconnect() }
        startup = task; await task.value
    }
    func reconnect() async {
        guard !starting else { return }; starting = true; defer { starting = false }
        do { try await launcher.ensureStarted(); serviceError = nil; sharing.start(); remote.start(); await sharing.refresh(); await remote.refresh() }
        catch { serviceError = (error as? CmuxRemoteCore.BridgeError)?.code ?? "connection_failed" }
    }
    func applyStatePath() async {
        guard statePath.hasPrefix("/"), statePath.utf8.count < 80, !starting else { serviceError = "invalid_state_path"; return }
        sharing.stopObservation(); remote.stop()
        let directory = URL(fileURLWithPath: statePath)
        let owner = UnixSocketClient(path: directory.appendingPathComponent("owner.sock").path)
        remote = MacCompanionModel(owner: owner, discovery: OwnerBridgeDiscovery(owner: owner))
        sharing = MacSharingModel(owner: owner)
        launcher = MacResidentLauncher(executable: executable, directory: directory, owner: owner)
        preferences.set(statePath, forKey: "bridgeStatePath")
        await reconnect()
    }
}

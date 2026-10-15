import Foundation
import Observation
import CmuxRemoteMac
import CmuxRemoteCore

/// The Bridge log window's state: a bounded tail read off the main thread, re-read on a short cadence only
/// while the window is on screen and not paused.
@MainActor @Observable final class MacLogModel {
    enum Status: Equatable { case idle, loaded, missing, failed(String) }
    private(set) var lines: [BridgeLogLine] = []
    private(set) var status = Status.idle
    var filter = BridgeLogFilter()
    var paused = false
    /// Set by the window owner from the window's occlusion state; a closed or hidden window reads nothing.
    var windowVisible = false
    /// The state directory of the resident this app controls; changing it discards the previous Bridge's lines.
    var directory: URL { didSet { if directory != oldValue { lines = []; status = .idle } } }
    private let tail: BridgeLogTail
    private let interval: Duration
    private var reading = false
    init(directory: URL, tail: BridgeLogTail, interval: Duration) {
        self.directory = directory; self.tail = tail; self.interval = interval
    }
    var live: Bool { windowVisible && !paused }
    var file: URL { BridgeLogTail.file(in: directory) }
    var shown: [BridgeLogLine] { filter.apply(lines) }
    /// Runs for the lifetime of the calling task. A paused window keeps what it shows; it reads once only when
    /// it has never read.
    func follow() async {
        guard live else { if status == .idle { await refresh() }; return }
        while live, !Task.isCancelled {
            await refresh()
            do { try await Task.sleep(for: interval) } catch { return }
        }
    }
    func refresh() async {
        guard !reading else { return }
        reading = true; defer { reading = false }
        let tail = tail, directory = directory
        let result = await Task.detached(priority: .utility) { Result { try tail.read(directory: directory) } }.value
        guard !Task.isCancelled, directory == self.directory else { return }
        switch result {
        case .success(let read?): if read != lines { lines = read }; status = .loaded
        case .success(nil): lines = []; status = .missing
        case .failure(let error): lines = []; status = .failed((error as? BridgeError)?.code ?? "log_unreadable")
        }
    }
    /// The filtered lines a user copies into a report, after one line naming this app build and macOS version.
    func exportText(bundle: Bundle, system: ProcessInfo) -> String {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let header = "CmuxRemote " + version + " (" + build + ") · macOS " + system.operatingSystemVersionString
        return ([header] + shown.map(\.text)).joined(separator: "\n") + "\n"
    }
}

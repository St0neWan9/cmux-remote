import Foundation
import Observation
import CmuxRemoteCore
import CmuxRemoteClient

/// Phone navigation owns UI state; all transport access is through the client.
@MainActor @Observable
final class AppModel {
    var client: RemoteClient?
    var sessions: [SessionDescriptor] = []
    var error: String?
    var loading = false
    var host = ""
    private let store = PairingStore()
    private var restored = false
    func restorePairing() {
        guard !restored else { return }; restored = true
        if let pairing = store.load() { host = pairing.host; client = RemoteClient(pairing: pairing) }
    }
    func pair(_ pairing: PairingConfiguration) async {
        loading = true; error = nil; defer { loading = false }
        let candidate = RemoteClient(pairing: pairing)
        do {
            _ = try await candidate.get("/v1/status", as: JSONValue.self)
            try store.save(pairing); client = candidate; host = pairing.host
        } catch { candidate.close(); self.error = ErrorPresentation().message(error) }
    }
    func refresh() async {
        guard let client else { return }; loading = true; defer { loading = false }
        do { sessions = try await client.get("/v1/sessions", as: [SessionDescriptor].self); error = nil }
        catch { self.error = ErrorPresentation().message(error) }
    }
    func unpair() { client?.close(); client = nil; sessions = []; store.remove() }
}

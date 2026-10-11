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
        #if DEBUG
        // Only an explicit isolated-Simulator test injection can enroll a fixture host.
        if let path = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let value = try? JSONDecoder().decode(PairingConfiguration.self, from: data),
           let pairing = try? PairingConfiguration(host: value.host, port: value.port, token: value.token, certificateSHA256: value.certificateSHA256) {
            Task { await pair(pairing) }; return
        }
        #endif
        if let pairing = store.load() { host = pairing.host; client = RemoteClient(pairing: pairing) }
    }
    func pair(_ pairing: PairingConfiguration) async {
        loading = true; error = nil; defer { loading = false }
        let candidate = RemoteClient(pairing: pairing)
        do {
            _ = try await candidate.get("/v1/status", as: JSONValue.self)
            try store.save(pairing); client = candidate; host = pairing.host
        } catch {
            #if DEBUG
            let value = error as NSError
            print("Pairing failed: \((error as? BridgeError)?.code ?? value.domain) \(value.code)")
            #endif
            candidate.close(); self.error = ErrorPresentation().message(error)
        }
    }
    func refresh() async {
        guard let client else { return }; loading = true; defer { loading = false }
        do {
            let discovered = try await client.get("/v1/sessions", as: [SessionDescriptor].self)
            sessions = discovered.sorted {
                if $0.writable != $1.writable { return $0.writable }
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            error = nil
        }
        catch { self.error = ErrorPresentation().message(error) }
    }
    func unpair() { client?.close(); client = nil; sessions = []; store.remove() }
}

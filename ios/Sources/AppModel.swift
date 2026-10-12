import Foundation
import Observation
import CmuxRemoteCore
import CmuxRemoteClient

/// Owns discovery, explicit first-use trust, enrollment progress and saved per-device authorization.
@MainActor @Observable
final class AppModel {
    var client: RemoteClient?
    var sessions: [SessionDescriptor] = []
    var workspaces: [WorkspaceSummary] = []
    var hostIdentity: String? { saved?.host.id }
    var hostCertificate: String? { saved?.host.certificateSHA256 }
    var endpoint: String? { saved.map { $0.endpoint.host + ":" + String($0.endpoint.port) } }
    var error: String?
    var loading = false
    var host = ""
    var discovered: [DiscoveredBridge] = []
    var pendingEnrollment: (any DeviceEnrolling)?
    var enrollmentState = ""
    private let discovery: BridgeDiscovery
    private let store: PairingStore
    private let pendingSends: PendingSendStore
    private let identityKey: @MainActor () throws -> Data
    private let makeEnrollment: @MainActor (SignedValue<EnrollmentBootstrap>, Data, BridgeEndpoint?) throws -> any DeviceEnrolling
    private let enrollmentTicks: @MainActor () -> (stream: AsyncStream<Void>, stop: @MainActor () -> Void)
    private let fetchSessions: @Sendable (RemoteClient) async throws -> [SessionDescriptor]
    private let fetchWorkspaces: @Sendable (RemoteClient) async throws -> [WorkspaceSummary]
    private var refreshGeneration = UUID()
    private var saved: AuthorizedConnection?
    private var enrollmentTask: Task<Void, Never>?
    @ObservationIgnored private var conversationModels: [String: ConversationModel] = [:]
    private var restored = false
    private var enrollmentActive = true
    private var enrollmentGeneration = UUID()
    private var monitorGeneration = UUID()
    init(discovery: BridgeDiscovery = BridgeDiscovery(), store: PairingStore = PairingStore(), pendingSends: PendingSendStore = PendingSendStore(),
         identityKey: @escaping @MainActor () throws -> Data = { try DeviceIdentityStore().privateKey() },
         makeEnrollment: @escaping @MainActor (SignedValue<EnrollmentBootstrap>, Data, BridgeEndpoint?) throws -> any DeviceEnrolling = { bootstrap, key, endpoint in try EnrollmentClient(bootstrap: bootstrap, privateKey: key, name: "cmux iPhone", kind: "iphone", endpoint: endpoint) },
         fetchSessions: @escaping @Sendable (RemoteClient) async throws -> [SessionDescriptor] = { try await $0.get("/v1/sessions", as: [SessionDescriptor].self) },
         fetchWorkspaces: @escaping @Sendable (RemoteClient) async throws -> [WorkspaceSummary] = { client in
             let value = try await client.get("/v1/workspaces", as: JSONValue.self)
             return (value["workspaces"].array ?? []).compactMap(WorkspaceSummary.init(json:))
         },
         enrollmentTicks: @escaping @MainActor () -> (stream: AsyncStream<Void>, stop: @MainActor () -> Void) = { let ticker = RefreshTicker(); return (ticker.start(), { ticker.stop() }) }) {
        self.discovery = discovery; self.store = store; self.pendingSends = pendingSends; self.identityKey = identityKey; self.makeEnrollment = makeEnrollment; self.enrollmentTicks = enrollmentTicks
        self.fetchSessions = fetchSessions; self.fetchWorkspaces = fetchWorkspaces
    }
    func restorePairing() {
        guard !restored else { return }; restored = true
        #if DEBUG
        if let path = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_ENROLLMENT_PATH"], let text = try? String(contentsOfFile: path, encoding: .utf8) {
            Task { await enrollQR(text.trimmingCharacters(in: .whitespacesAndNewlines)) }; return
        }
        if let path = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_PAIRING_PATH"], let data = try? Data(contentsOf: URL(fileURLWithPath: path)), let value = try? JSONDecoder().decode(PairingConfiguration.self, from: data) {
            Task { await pair(value) }; return
        }
        #endif
        if let value = store.loadConnection(), let remote = try? RemoteClient(connection: value) {
            saved = value; host = value.host.name; client = remote
        } else if store.legacyEnabled(), let legacy = store.load() { host = legacy.host; client = RemoteClient(pairing: legacy) }
        else if store.load() != nil { error = String(localized: "pair.legacy_migration") }
    }
    func discover() async {
        defer { discovery.stop() }
        for await values in discovery.start() {
            guard !Task.isCancelled else { break }; discovered = values
            if let saved, let peer = values.first(where: { $0.host.id == saved.host.id }) {
                do {
                    let endpoint = try await discovery.resolve(peer)
                    let relocated = try saved.relocated(to: endpoint, advertisedHost: peer.host)
                    if relocated.endpoint != saved.endpoint {
                        let candidate = try RemoteClient(connection: relocated)
                        do { _ = try await candidate.get("/v1/status", as: JSONValue.self) }
                        catch { candidate.close(); throw error }
                        guard !Task.isCancelled, self.saved?.host.id == saved.host.id, self.saved?.grant.signature == saved.grant.signature, self.saved?.endpoint == saved.endpoint, let currentClient = client else { candidate.close(); continue }
                        try store.saveConnection(relocated)
                        try await currentClient.relocate(relocated); candidate.close()
                        guard self.saved?.host.id == saved.host.id, self.saved?.grant.signature == saved.grant.signature, client === currentClient else { continue }
                        self.saved = relocated; error = nil; await refresh()
                    }
                } catch { if !Task.isCancelled { self.error = ErrorPresentation().message(error) } }
            }
        }
    }
    /// Called only after the user explicitly confirms a discovered identity in the UI.
    func enrollDiscovered(_ peer: DiscoveredBridge) async {
        let generation = UUID(); enrollmentGeneration = generation
        do {
            let endpoint = try await discovery.resolve(peer)
            let bootstrap = try await EnrollmentBootstrapClient().fetch(endpoint: endpoint, trustedHost: peer.host)
            guard enrollmentGeneration == generation else { return }
            await enroll(bootstrap, endpoint: endpoint)
        } catch { if enrollmentGeneration == generation { self.error = ErrorPresentation().message(error) } }
    }
    func enrollQR(_ text: String) async {
        do {
            let value: SignedValue<EnrollmentBootstrap>
            if text.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
                value = try JSONDecoder().decode(SignedValue<EnrollmentBootstrap>.self, from: Data(text.utf8))
                try EnrollmentLinkCodec().validate(value, now: Int(Date().timeIntervalSince1970))
            } else { value = try EnrollmentLinkCodec().decode(text) }
            await enroll(value)
        }
        catch { self.error = ErrorPresentation().message(error) }
    }
    private func enroll(_ bootstrap: SignedValue<EnrollmentBootstrap>, endpoint: BridgeEndpoint? = nil) async {
        let generation = UUID(); enrollmentGeneration = generation
        let previous = pendingEnrollment; pendingEnrollment = nil; stopEnrollmentMonitor()
        if let previous { try? await previous.cancel(); previous.close() }
        guard enrollmentGeneration == generation else { return }
        error = nil; loading = true
        do {
            let enrollment = try makeEnrollment(bootstrap, identityKey(), endpoint)
            pendingEnrollment = enrollment
            let status = try await enrollment.submit()
            guard enrollmentGeneration == generation, pendingEnrollment === enrollment else { enrollment.close(); return }
            enrollmentState = status.state; loading = false
            startEnrollmentMonitor()
        } catch {
            guard enrollmentGeneration == generation else { return }
            loading = false; pendingEnrollment?.close(); pendingEnrollment = nil; self.error = ErrorPresentation().message(error)
        }
    }
    func resumeEnrollment() { enrollmentActive = true; startEnrollmentMonitor() }
    private func startEnrollmentMonitor() {
        guard enrollmentActive, enrollmentTask == nil, let enrollment = pendingEnrollment else { return }
        let generation = UUID(); monitorGeneration = generation
        enrollmentTask = Task {
            defer { if monitorGeneration == generation { enrollmentTask = nil } }
                // Foreground enrollment status cadence; cancellation stops active network requests.
                let ticker = enrollmentTicks(); defer { ticker.stop() }
                for await _ in ticker.stream {
                    guard !Task.isCancelled else { break }
                    do {
                        let status = try await enrollment.status()
                        guard !Task.isCancelled, pendingEnrollment === enrollment else { break }
                        enrollmentState = status.state; error = nil
                        if status.state == "approved" {
                            let value = try enrollment.connection(from: status); let candidate = try RemoteClient(connection: value)
                            do {
                                _ = try await candidate.get("/v1/status", as: JSONValue.self)
                                guard !Task.isCancelled, pendingEnrollment === enrollment else { candidate.close(); break }
                                try store.saveConnection(value); store.disableLegacy()
                            }
                            catch { candidate.close(); throw error }
                            client?.close(); client = candidate; saved = value; host = value.host.name; pendingEnrollment = nil; enrollment.close(); await refresh(); break
                        }
                        if ["denied", "expired", "cancelled", "revoked"].contains(status.state) { pendingEnrollment = nil; enrollment.close(); error = String(localized: "pair.enrollment_ended"); break }
                    } catch {
                        guard !Task.isCancelled, pendingEnrollment === enrollment else { break }
                        self.error = ErrorPresentation().message(error)
                        if let network = error as? URLError,
                           [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(network.code),
                           enrollment.request.value.expiresAt > Int(Date().timeIntervalSince1970) { continue }
                        break
                    }
                }
            }
    }
    func pauseEnrollment() { enrollmentActive = false; stopEnrollmentMonitor() }
    private func stopEnrollmentMonitor() { monitorGeneration = UUID(); enrollmentTask?.cancel(); enrollmentTask = nil }
    func cancelEnrollment() async {
        enrollmentGeneration = UUID(); stopEnrollmentMonitor(); loading = false; error = nil
        let previous = pendingEnrollment; pendingEnrollment = nil; enrollmentState = ""
        if let previous { try? await previous.cancel(); previous.close() }
    }
    /// Legacy is an explicit advanced fallback; it is never promoted to a new device identity.
    func pair(_ pairing: PairingConfiguration) async {
        loading = true; error = nil; defer { loading = false }
        let candidate = RemoteClient(pairing: pairing)
        do { _ = try await candidate.get("/v1/status", as: JSONValue.self); try store.save(pairing); try store.enableLegacy(); client = candidate; host = pairing.host }
        catch { candidate.close(); self.error = ErrorPresentation().message(error) }
    }
    func refresh() async {
        guard let client else { return }; let request = UUID(); refreshGeneration = request; loading = true
        defer { if refreshGeneration == request { loading = false } }
        do {
            let discovered = client.allows(.conversationRead) ? try await fetchSessions(client) : []
            guard self.client === client, refreshGeneration == request, !Task.isCancelled else { return }
            sessions = discovered.sorted { if $0.writable != $1.writable { return $0.writable }; return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            if client.allows(.workspaceRead) {
                let metadata = try await fetchWorkspaces(client)
                guard self.client === client, refreshGeneration == request, !Task.isCancelled else { return }
                workspaces = metadata
            }
            error = nil
        } catch { if self.client === client, refreshGeneration == request, !Task.isCancelled { self.error = ErrorPresentation().message(error) } }
    }
    /// Own in-flight and unresolved sends across pushed-view navigation.
    func conversation(session: SessionDescriptor, client: RemoteClient) -> ConversationModel {
        let key = client.operationRecoveryScope + ":" + session.id
        if let existing = conversationModels[key] { return existing }
        if conversationModels.count >= 32 { conversationModels = conversationModels.filter { $0.value.busy } }
        let store = pendingSends; let scope = client.operationRecoveryScope; let id = session.id
        let model = ConversationModel(session: session, client: client,
            loadRecovery: { try await store.load(scope: scope, sessionID: id) },
            saveRecovery: { try await store.save($0, scope: scope, sessionID: id) })
        conversationModels[key] = model
        return model
    }
    func unpair() { conversationModels.removeAll(); refreshGeneration = UUID(); loading = false; enrollmentGeneration = UUID(); stopEnrollmentMonitor(); client?.close(); client = nil; saved = nil; sessions = []; workspaces = []; store.remove(); store.removeConnection(); store.disableLegacy() }
}

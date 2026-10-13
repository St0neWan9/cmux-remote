import Foundation
import Observation
import CmuxRemoteCore
import CmuxRemoteClient

/// Owns discovery, explicit first-use trust, enrollment progress and every approved Mac's authorization.
@MainActor @Observable
final class AppModel {
    /// Approved Macs in the order they were added; conversations from all of them are shown together.
    var links: [HostLink] = []
    /// The first Mac's client. Assigning one replaces all Macs with a single unsaved link (fixtures, legacy).
    var client: RemoteClient? {
        get { links.first?.client }
        set { links = newValue.map { [HostLink(id: "primary", name: host, client: $0, connection: nil)] } ?? [] }
    }
    var sessions: [SessionDescriptor] { hostedSessions.map(\.session) }
    var hostedSessions: [HostedSession] = []
    var workspaces: [WorkspaceSummary] = []
    /// Workspace ID to the Mac that owns it, for labels when several Macs are connected.
    var workspaceHosts: [String: String] = [:]
    var hostErrors: [String: String] = [:]
    var error: String?
    var loading = false
    var host = ""
    var discovered: [DiscoveredBridge] = []
    /// Macs listed by a known relay; each entry is host-signed and verified like a scanned QR.
    var relayHosts: [SignedValue<EnrollmentBootstrap>] = []
    var relayOrigins: [String] = []
    var relayError: String?
    /// The pairing screen over the conversation list while another Mac is added.
    var addingDevice = false
    var pendingEnrollment: (any DeviceEnrolling)?
    var enrollmentState = ""
    private let discovery: BridgeDiscovery
    private let store: PairingStore
    private let makeSpeechInput: @MainActor () -> any SpeechInputServing
    private let pendingSends: PendingSendStore
    private let identityKey: @MainActor () throws -> Data
    private let makeEnrollment: @MainActor (SignedValue<EnrollmentBootstrap>, Data, BridgeEndpoint?) throws -> any DeviceEnrolling
    private let enrollmentTicks: @MainActor () -> (stream: AsyncStream<Void>, stop: @MainActor () -> Void)
    private let fetchSessions: @Sendable (RemoteClient) async throws -> [SessionDescriptor]
    private let fetchWorkspaces: @Sendable (RemoteClient) async throws -> [WorkspaceSummary]
    private var refreshGeneration = UUID()
    private var perHost: [String: (sessions: [SessionDescriptor], workspaces: [WorkspaceSummary])] = [:]
    private let directory: @Sendable (String) async throws -> [SignedValue<EnrollmentBootstrap>]
    private var enrollmentTask: Task<Void, Never>?
    @ObservationIgnored private var conversationModels: [String: ConversationModel] = [:]
    private var restored = false
    private var enrollmentActive = true
    private var enrollmentGeneration = UUID()
    private var monitorGeneration = UUID()
    init(discovery: BridgeDiscovery = BridgeDiscovery(), store: PairingStore = PairingStore(), pendingSends: PendingSendStore = PendingSendStore(),
         makeSpeechInput: @escaping @MainActor () -> any SpeechInputServing = { UnavailableSpeechInput() },
         identityKey: @escaping @MainActor () throws -> Data = { try DeviceIdentityStore().privateKey() },
         makeEnrollment: @escaping @MainActor (SignedValue<EnrollmentBootstrap>, Data, BridgeEndpoint?) throws -> any DeviceEnrolling = { bootstrap, key, endpoint in try EnrollmentClient(bootstrap: bootstrap, privateKey: key, name: "cmux iPhone", kind: "iphone", endpoint: endpoint) },
         fetchSessions: @escaping @Sendable (RemoteClient) async throws -> [SessionDescriptor] = { try await $0.get("/v1/sessions", as: [SessionDescriptor].self) },
         fetchWorkspaces: @escaping @Sendable (RemoteClient) async throws -> [WorkspaceSummary] = { client in
             let value = try await client.get("/v1/workspaces", as: JSONValue.self)
             return (value["workspaces"].array ?? []).compactMap(WorkspaceSummary.init(json:))
         },
         enrollmentTicks: @escaping @MainActor () -> (stream: AsyncStream<Void>, stop: @MainActor () -> Void) = { let ticker = RefreshTicker(); return (ticker.start(), { ticker.stop() }) },
         directory: @escaping @Sendable (String) async throws -> [SignedValue<EnrollmentBootstrap>] = { try await RelayDirectoryClient().hosts(origin: $0) }) {
        self.makeSpeechInput = makeSpeechInput; self.directory = directory
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
        relayOrigins = store.relayOrigins()
        for value in store.loadConnections() {
            guard let remote = try? RemoteClient(connection: value) else { continue }
            links.append(HostLink(id: value.host.id, name: value.host.name, client: remote, connection: value))
            learnRelay(value)
        }
        host = links.first?.name ?? ""
        if links.isEmpty {
            if store.legacyEnabled(), let legacy = store.load() { host = legacy.host; links = [HostLink(id: "legacy", name: legacy.host, client: RemoteClient(pairing: legacy), connection: nil)] }
            else if store.load() != nil { error = String(localized: "pair.legacy_migration") }
        }
    }
    /// Approved Macs teach their relay origin, so other Macs on the same relay can be listed.
    private func learnRelay(_ connection: AuthorizedConnection) {
        guard let origin = connection.endpoint.relay?.origin, !relayOrigins.contains(origin) else { return }
        relayOrigins.append(origin); store.saveRelayOrigins(relayOrigins)
    }
    func addRelayOrigin(_ text: String) async {
        do {
            let origin = try RelayOrigin(text.trimmingCharacters(in: .whitespacesAndNewlines)).value
            if !relayOrigins.contains(origin) { relayOrigins.append(origin); store.saveRelayOrigins(relayOrigins) }
            relayError = nil; await refreshRelayDirectory()
        } catch { relayError = ErrorPresentation().message(error) }
    }
    func removeRelayOrigin(_ origin: String) {
        relayOrigins.removeAll { $0 == origin }; store.saveRelayOrigins(relayOrigins)
        relayHosts.removeAll { $0.value.endpoint.relay?.origin == origin }
    }
    /// Reads every known relay; one unreachable relay does not hide the others' Macs.
    func refreshRelayDirectory() async {
        var found: [String: SignedValue<EnrollmentBootstrap>] = [:], failure: String?
        for origin in relayOrigins {
            do { for entry in try await directory(origin) where found[entry.value.host.id] == nil { found[entry.value.host.id] = entry } }
            catch { failure = ErrorPresentation().message(error) }
        }
        relayHosts = found.values.sorted { $0.value.host.name.localizedStandardCompare($1.value.host.name) == .orderedAscending }
        relayError = relayHosts.isEmpty ? failure : nil
    }
    func isApproved(_ hostID: String) -> Bool { links.contains { $0.id == hostID } }
    /// Called only after the user confirms a listed identity; the Mac owner still approves this exact device.
    func enrollListed(_ bootstrap: SignedValue<EnrollmentBootstrap>) async {
        do { try EnrollmentLinkCodec().validate(bootstrap, now: Int(Date().timeIntervalSince1970)); await enroll(bootstrap) }
        catch { self.error = ErrorPresentation().message(error) }
    }
    func discover() async {
        defer { discovery.stop() }
        for await values in discovery.start() {
            guard !Task.isCancelled else { break }; discovered = values
            for link in links {
                guard let saved = link.connection, let peer = values.first(where: { $0.host.id == saved.host.id }) else { continue }
                do {
                    let endpoint = try await discovery.resolve(peer)
                    let relocated = try saved.relocated(to: endpoint, advertisedHost: peer.host)
                    if relocated.endpoint != saved.endpoint {
                        let candidate = try RemoteClient(connection: relocated)
                        do { _ = try await candidate.get("/v1/status", as: JSONValue.self) }
                        catch { candidate.close(); throw error }
                        guard !Task.isCancelled, let current = links.first(where: { $0.id == link.id }), current.client === link.client,
                              current.connection?.grant.signature == saved.grant.signature, current.connection?.endpoint == saved.endpoint else { candidate.close(); continue }
                        try store.saveConnection(relocated)
                        try await link.client.relocate(relocated); candidate.close()
                        guard let index = links.firstIndex(where: { $0.id == link.id }), links[index].client === link.client else { continue }
                        links[index].connection = relocated; error = nil; await refresh()
                    }
                } catch { if !Task.isCancelled { self.hostErrors[link.id] = ErrorPresentation().message(error) } }
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
                            install(HostLink(id: value.host.id, name: value.host.name, client: candidate, connection: value))
                            learnRelay(value); pendingEnrollment = nil; addingDevice = false; enrollment.close(); await refresh(); break
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
        do {
            _ = try await candidate.get("/v1/status", as: JSONValue.self); try store.save(pairing); try store.enableLegacy()
            install(HostLink(id: "legacy", name: pairing.host, client: candidate, connection: nil)); addingDevice = false
        }
        catch { candidate.close(); self.error = ErrorPresentation().message(error) }
    }
    /// A re-approved Mac replaces its old link in place; a new Mac is appended.
    private func install(_ link: HostLink) {
        if let index = links.firstIndex(where: { $0.id == link.id }) { let old = links[index].client; links[index] = link; if old !== link.client { old.close() } }
        else { links.append(link) }
        host = links.first?.name ?? link.name
    }
    /// Reads every Mac concurrently; one unreachable Mac keeps its last list and reports its own error.
    func refresh() async {
        let targets = links; guard !targets.isEmpty else { return }
        let request = UUID(); refreshGeneration = request; loading = true
        defer { if refreshGeneration == request { loading = false } }
        let fetchSessions = fetchSessions, fetchWorkspaces = fetchWorkspaces
        let results = await withTaskGroup(of: (String, Result<([SessionDescriptor], [WorkspaceSummary]?), any Error>).self) { group in
            for link in targets {
                let client = link.client
                group.addTask {
                    do {
                        let sessions = client.allows(.conversationRead) ? try await fetchSessions(client) : []
                        let workspaces = client.allows(.workspaceRead) ? try await fetchWorkspaces(client) : nil
                        return (link.id, .success((sessions, workspaces)))
                    } catch { return (link.id, .failure(error)) }
                }
            }
            var collected: [String: Result<([SessionDescriptor], [WorkspaceSummary]?), any Error>] = [:]
            for await (id, result) in group { collected[id] = result }
            return collected
        }
        guard refreshGeneration == request, !Task.isCancelled else { return }
        for link in targets {
            guard links.contains(where: { $0.id == link.id && $0.client === link.client }), let result = results[link.id] else { continue }
            switch result {
            case .success(let (sessions, workspaces)):
                let ordered = sessions.sorted { if $0.writable != $1.writable { return $0.writable }; return $0.title.localizedStandardCompare($1.title) == .orderedAscending }
                perHost[link.id] = (ordered, workspaces ?? perHost[link.id]?.workspaces ?? []); hostErrors[link.id] = nil
            case .failure(let failure): hostErrors[link.id] = ErrorPresentation().message(failure)
            }
        }
        publish()
        for link in targets where link.connection != nil {
            guard let updated = try? await link.client.refreshRelayHint(), let index = links.firstIndex(where: { $0.id == link.id && $0.client === link.client }) else { continue }
            try? store.saveConnection(updated); links[index].connection = updated; learnRelay(updated)
        }
    }
    /// Rebuilds the combined lists in Mac order from each Mac's last successful read.
    private func publish() {
        let current = links.filter { perHost[$0.id] != nil }
        hostedSessions = current.flatMap { link in perHost[link.id]!.sessions.map { HostedSession(hostID: link.id, hostName: link.name, session: $0) } }
        workspaces = current.flatMap { perHost[$0.id]!.workspaces }
        workspaceHosts = Dictionary(current.flatMap { link in perHost[link.id]!.workspaces.map { ($0.id, link.name) } }, uniquingKeysWith: { first, _ in first })
        error = links.compactMap { link in hostErrors[link.id].map { links.count > 1 ? link.name + "：" + $0 : $0 } }.first
    }
    func link(for hostID: String) -> HostLink? { links.first { $0.id == hostID } }
    /// Own in-flight and unresolved sends across pushed-view navigation.
    func conversation(session: SessionDescriptor, client: RemoteClient) -> ConversationModel {
        let key = client.operationRecoveryScope + ":" + session.id
        if let existing = conversationModels[key] { return existing }
        if conversationModels.count >= 32 { conversationModels = conversationModels.filter { $0.value.busy || $0.value.pendingSend != nil } }
        let store = pendingSends; let scope = client.operationRecoveryScope; let id = session.id
        let model = ConversationModel(session: session, client: client, speechInput: makeSpeechInput(),
            loadRecovery: { try await store.load(scope: scope, sessionID: id) },
            saveRecovery: { try await store.save($0, scope: scope, sessionID: id) })
        conversationModels[key] = model
        return model
    }
    /// Removes one Mac from this phone only; the Mac owner revokes the device separately.
    func remove(hostID: String) {
        guard let index = links.firstIndex(where: { $0.id == hostID }) else { return }
        let removed = links.remove(at: index), scope = removed.client.operationRecoveryScope + ":"
        for (key, model) in conversationModels where key.hasPrefix(scope) { model.suspendReads(); model.speech.cancel(); conversationModels[key] = nil }
        removed.client.close(); perHost[hostID] = nil; hostErrors[hostID] = nil; refreshGeneration = UUID(); loading = false
        if removed.connection != nil { store.removeConnection(hostID: hostID) } else { store.remove(); store.disableLegacy() }
        host = links.first?.name ?? ""; publish()
        if links.isEmpty { enrollmentGeneration = UUID(); stopEnrollmentMonitor() }
    }
}

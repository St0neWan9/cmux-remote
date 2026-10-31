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
    /// Each Mac's items waiting for a reply, kept current while the app is in the foreground.
    var pending: [String: PendingFeed] = [:]
    var workspaces: [WorkspaceSummary] = []
    /// Workspace ID to the Mac that owns it, for labels when several Macs are connected.
    var workspaceHosts: [String: String] = [:]
    /// Approved workspaces on Macs that let this device start sessions.
    var startTargets: [StartTarget] = []
    var hostErrors: [String: String] = [:]
    /// Each Mac's link as the client reports it; a Mac never dialed yet has no entry.
    var linkStates: [String: LinkState] = [:]
    /// When the app last left the foreground, so a short switch does not force every link to dial again.
    @ObservationIgnored var backgroundedAt: Date?
    /// Paces automatic redials of lost Macs; it outlives one supervision pass so a person's retry can reset it.
    @ObservationIgnored let reconnectSchedule = ReconnectSchedule()
    /// Each Mac's model choices per agent, shared by its conversations.
    @ObservationIgnored let modelChoices = ModelChoiceCache()
    /// Macs the schedule keeps retrying in the background: the pages stop showing their dial and their failure,
    /// until one of them connects or a person asks for a retry.
    var quietHosts: Set<String> = []
    var error: String?
    var loading = false
    var host = ""
    var discovered: [DiscoveredBridge] = []
    /// Macs listed by a known relay; each entry is host-signed and verified like a scanned QR.
    var relayHosts: [SignedValue<EnrollmentBootstrap>] = []
    var relayOrigins: [String] = []
    var relayError: String?
    var relayLoading = false
    /// The pairing screen pushed over the conversation list while another Mac is added.
    var addingDevice = false
    /// Whether the sidebar is open. It lives here so a pushed page keeps the drawer open behind it, and so
    /// returning from one lands on the drawer rather than the bare list.
    var sidebarOpen = false
    var pendingEnrollment: (any DeviceEnrolling)?
    var enrollmentState = ""
    private let discovery: BridgeDiscovery
    private let store: PairingStore
    /// Conversations read before, kept on disk so reopening one is immediate.
    private let conversations = ConversationCache()
    /// Every page a conversation was read with, kept on the phone so reading back never asks the Mac again.
    let conversationStore = ConversationStore()
    private let makeSpeechInput: @MainActor () -> any SpeechInputServing
    private let pendingSends: PendingSendStore
    private let identityKey: @MainActor () throws -> Data
    private let makeEnrollment: @MainActor (SignedValue<EnrollmentBootstrap>, Data, BridgeEndpoint?, [ClientCapability]) throws -> any DeviceEnrolling
    private let enrollmentTicks: @MainActor () -> (stream: AsyncStream<Void>, stop: @MainActor () -> Void)
    private let fetchSessions: @Sendable (RemoteClient) async throws -> [SessionDescriptor]
    private let fetchWorkspaces: @Sendable (RemoteClient) async throws -> [WorkspaceSummary]
    private var refreshGeneration = UUID()
    private var perHost: [String: (sessions: [SessionDescriptor], workspaces: [WorkspaceSummary])] = [:]
    private let directory: @Sendable (String) async throws -> [SignedValue<EnrollmentBootstrap>]
    private var enrollmentTask: Task<Void, Never>?
    @ObservationIgnored private var conversationModels: [String: ConversationModel] = [:]
    @ObservationIgnored private let runningSync = RunningSessionSync()
    @ObservationIgnored private var followingSessions = false
    private var restored = false
    private var enrollmentActive = true
    private var enrollmentGeneration = UUID()
    private var monitorGeneration = UUID()
    init(discovery: BridgeDiscovery = BridgeDiscovery(), store: PairingStore = PairingStore(), pendingSends: PendingSendStore = PendingSendStore(),
         makeSpeechInput: @escaping @MainActor () -> any SpeechInputServing = { UnavailableSpeechInput() },
         identityKey: @escaping @MainActor () throws -> Data = { try DeviceIdentityStore().privateKey() },
         makeEnrollment: @escaping @MainActor (SignedValue<EnrollmentBootstrap>, Data, BridgeEndpoint?, [ClientCapability]) throws -> any DeviceEnrolling = { bootstrap, key, endpoint, capabilities in try EnrollmentClient(bootstrap: bootstrap, privateKey: key, name: "cmux iPhone", kind: "iphone", capabilities: capabilities, endpoint: endpoint) },
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
            guard let remote = try? RemoteClient(connection: value, trace: diagLinkTrace(host: value.host.id)) else { continue }
            links.append(HostLink(id: value.host.id, name: value.host.name, client: remote, connection: value))
            learnRelay(value)
        }
        host = links.first?.name ?? ""
        if links.isEmpty {
            if store.legacyEnabled(), let legacy = store.load() { host = legacy.host; links = [HostLink(id: "legacy", name: legacy.host, client: RemoteClient(pairing: legacy, trace: diagLinkTrace(host: "legacy")), connection: nil)] }
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
        guard !relayOrigins.isEmpty else { relayHosts = []; relayError = nil; return }
        relayLoading = true; defer { relayLoading = false }
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
        #if DEBUG
        // Screenshot and UI runs need a deterministic list: the real one names whatever Macs are on the
        // network, which must not end up in a store listing.
        if let path = ProcessInfo.processInfo.environment["CMUX_REMOTE_TEST_NEARBY_PATH"],
           let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
           let entries = try? JSONDecoder().decode([TestNearbyEntry].self, from: data) {
            discovered = entries.map { entry in
                let host = HostIdentity(id: entry.id, publicKey: entry.id, certificateSHA256: entry.id, name: entry.name)
                return DiscoveredBridge(host: host, service: .hostPort(host: .ipv4(.loopback), port: 1))
            }
            return
        }
        #endif
        defer { discovery.stop() }
        for await values in discovery.start() {
            guard !Task.isCancelled else { break }; discovered = values
            for link in links {
                guard let saved = link.connection, let peer = values.first(where: { $0.host.id == saved.host.id }) else { continue }
                do {
                    let endpoint = try await discovery.resolve(peer)
                    let relocated = try saved.relocated(to: endpoint, advertisedHost: peer.host)
                    if relocated.endpoint != saved.endpoint {
                        let candidate = try RemoteClient(connection: relocated, trace: diagLinkTrace(host: relocated.host.id))
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
            var enrollment = try makeEnrollment(bootstrap, identityKey(), endpoint, EnrollmentClient.phoneCapabilities)
            pendingEnrollment = enrollment
            let status: EnrollmentStatus
            do { status = try await enrollment.submit() }
            catch let failure as BridgeError where failure.code == "outcome_unknown" && enrollment.request.value.scope.capabilities.contains(.conversationStart) {
                // An older Bridge closes the link on a capability it cannot decode; ask again without starting sessions.
                guard enrollmentGeneration == generation, pendingEnrollment === enrollment else { enrollment.close(); return }
                enrollment.close()
                enrollment = try makeEnrollment(bootstrap, identityKey(), endpoint, EnrollmentClient.previousPhoneCapabilities)
                pendingEnrollment = enrollment
                status = try await enrollment.submit()
            }
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
                            let value = try enrollment.connection(from: status); let candidate = try RemoteClient(connection: value, trace: diagLinkTrace(host: value.host.id))
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
                        if EnrollmentPollRetry().shouldRetry(error, expiresAt: enrollment.request.value.expiresAt, now: Int(Date().timeIntervalSince1970)) { continue }
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
        let candidate = RemoteClient(pairing: pairing, trace: diagLinkTrace(host: "legacy"))
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
                perHost[link.id] = (ordered(sessions), workspaces ?? perHost[link.id]?.workspaces ?? []); hostErrors[link.id] = nil
                // A read that just succeeded proves the link, including for a transport that reports no states.
                if linkStates[link.id] != nil { linkStates[link.id] = .connected }
                quietHosts.remove(link.id)
            case .failure(let failure):
                // The Mac keeps its own error, so several Macs still say which one is down; the bar retries it.
                hostErrors[link.id] = ErrorPresentation().message(failure)
                if ErrorPresentation().isConnectivity(failure) { linkStates[link.id] = .disconnected }
            }
        }
        publish()
        for link in targets where link.connection != nil {
            guard let updated = try? await link.client.refreshRelayHint(), let index = links.firstIndex(where: { $0.id == link.id && $0.client === link.client }) else { continue }
            try? store.saveConnection(updated); links[index].connection = updated; learnRelay(updated)
        }
    }
    /// Most recent activity first; Bridges without activity times fall back to live-then-title order.
    private func ordered(_ sessions: [SessionDescriptor]) -> [SessionDescriptor] {
        sessions.sorted {
            let lhs = $0.updatedAt ?? .distantPast, rhs = $1.updatedAt ?? .distantPast
            if lhs != rhs { return lhs > rhs }
            if $0.writable != $1.writable { return $0.writable }
            return $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }
    /// Runs while the app is in the foreground: follows each Mac's session list, so running states stay current,
    /// and keeps conversations running off screen up to date. A list change is read at most once per interval.
    func followSessions(every interval: Duration = .seconds(8)) async {
        followingSessions = true; syncRunning()
        defer { followingSessions = false; runningSync.stop() }
        let followed = links.filter { $0.client.allows(.conversationRead) }.map { ($0.id, $0.client) }
        let feeds = links.filter { $0.client.allows(.feedRead) }.map { ($0.id, $0.client) }
        await withTaskGroup(of: Void.self) { group in
            // The reminder above the list counts items as they arrive; each change is read at once, since a pending
            // question is waiting on the reader.
            for (id, client) in feeds {
                group.addTask { [weak self] in
                    for await _ in client.changes(paths: ["/v1/feed"]) {
                        guard !Task.isCancelled else { return }
                        await self?.refreshPending(hostID: id, client: client)
                    }
                }
            }
            for (id, client) in followed {
                group.addTask { [weak self] in
                    for await _ in client.changes(paths: ["/v1/sessions"]) {
                        guard !Task.isCancelled else { return }
                        try? await Task.sleep(for: interval)
                        guard !Task.isCancelled else { return }
                        await self?.refreshSessions(hostID: id, client: client)
                    }
                }
            }
        }
    }
    /// A background wake: dials each Mac, reads the lists, then the conversations that are running or changed
    /// since this phone stored them, so switching to one later shows what it said meanwhile.
    func syncInBackground() async {
        restorePairing()
        guard BackgroundSync.enabled, !links.isEmpty else { return }
        let started = Date()
        let clients = links.map(\.client)
        await withTaskGroup(of: Void.self) { group in for client in clients { group.addTask { await client.reconnect() } } }
        guard !Task.isCancelled else { return }
        await refresh()
        var targets: [RunningSessionSync.Target] = []
        let recent = hostedSessions.sorted { ($0.session.updatedAt ?? .distantPast) > ($1.session.updatedAt ?? .distantPast) }.prefix(12)
        for hosted in recent {
            guard let client = link(for: hosted.hostID)?.client else { continue }
            let session = hosted.session, scope = client.operationRecoveryScope
            let stored = await conversations.storedAt(scope: scope, sessionID: session.id)
            var target = RunningSessionSync.Target(key: scope + ":" + session.id, running: session.state.hasPrefix("working"),
                                                   model: { [unowned self] in conversation(session: session, client: client) })
            if let updated = session.updatedAt { target.changedSinceStored = updated > (stored ?? .distantPast) }
            targets.append(target)
        }
        let read = await runningSync.pass(targets)
        diagLog(.info, category: "sync", "background pass read \(read) conversations in \(Int(Date().timeIntervalSince(started) * 1000))ms")
    }
    private func refreshPending(hostID: String, client: RemoteClient) async {
        guard let items = try? await client.get("/v1/feed", as: JSONValue.self)["items"].array,
              links.contains(where: { $0.id == hostID && $0.client === client }) else { return }
        let next = PendingFeed(items: items)
        if pending[hostID] != next { pending[hostID] = next }
    }
    /// Reads one Mac's sessions only; workspaces and relay hints wait for a full refresh.
    private func refreshSessions(hostID: String, client: RemoteClient) async {
        guard let sessions = try? await fetchSessions(client),
              links.contains(where: { $0.id == hostID && $0.client === client }) else { return }
        perHost[hostID] = (ordered(sessions), perHost[hostID]?.workspaces ?? []); hostErrors[hostID] = nil
        publish()
    }
    private func syncRunning() {
        guard followingSessions else { return }
        runningSync.update(hostedSessions.compactMap { hosted in
            guard let client = link(for: hosted.hostID)?.client else { return nil }
            let session = hosted.session
            return RunningSessionSync.Target(key: client.operationRecoveryScope + ":" + session.id, running: session.state.hasPrefix("working"),
                                             model: { [unowned self] in conversation(session: session, client: client) })
        })
    }
    /// Rebuilds the combined lists in Mac order from each Mac's last successful read.
    private func publish() {
        let current = links.filter { perHost[$0.id] != nil }
        hostedSessions = current.flatMap { link in perHost[link.id]!.sessions.map { HostedSession(hostID: link.id, hostName: link.name, session: $0) } }
        workspaces = current.flatMap { perHost[$0.id]!.workspaces }
        workspaceHosts = Dictionary(current.flatMap { link in perHost[link.id]!.workspaces.map { ($0.id, link.name) } }, uniquingKeysWith: { first, _ in first })
        startTargets = current.filter { $0.client.allows(.conversationStart) }.flatMap { link in
            perHost[link.id]!.workspaces.map { StartTarget(hostID: link.id, hostName: link.name, workspace: $0, client: link.client) }
        }
        error = links.compactMap { link in hostErrors[link.id].map { links.count > 1 ? link.name + "：" + $0 : $0 } }.first
        syncRunning()
    }
    func link(for hostID: String) -> HostLink? { links.first { $0.id == hostID } }
    /// The workspaces one Mac shares, from its last successful read.
    func workspaces(of hostID: String) -> [WorkspaceSummary] { perHost[hostID]?.workspaces ?? [] }
    /// Own in-flight and unresolved sends across pushed-view navigation.
    func conversation(session: SessionDescriptor, client: RemoteClient) -> ConversationModel {
        let key = client.operationRecoveryScope + ":" + session.id
        // The list was just read, so a page opened again starts from its state rather than the one it last saw.
        if let existing = conversationModels[key] { existing.updateSession(session); return existing }
        if conversationModels.count >= 32 { conversationModels = conversationModels.filter { $0.value.busy || $0.value.pendingSend != nil } }
        let store = pendingSends; let scope = client.operationRecoveryScope; let id = session.id
        let model = ConversationModel(session: session, client: client, speechInput: makeSpeechInput(),
            loadRecovery: { try await store.load(scope: scope, sessionID: id) },
            saveRecovery: { try await store.save($0, scope: scope, sessionID: id) },
            cache: conversations, store: conversationStore, modelCache: modelChoices)
        conversationModels[key] = model
        return model
    }
    /// Removes one Mac from this phone only; the Mac owner revokes the device separately.
    func remove(hostID: String) {
        guard let index = links.firstIndex(where: { $0.id == hostID }) else { return }
        let removed = links.remove(at: index), scope = removed.client.operationRecoveryScope + ":"
        for (key, model) in conversationModels where key.hasPrefix(scope) { model.suspendReads(); model.speech.cancel(); conversationModels[key] = nil }
        removed.client.close(); perHost[hostID] = nil; hostErrors[hostID] = nil; pending[hostID] = nil; refreshGeneration = UUID(); loading = false
        // A removed Mac's conversations are unreadable; their stored copies go with it.
        Task { await conversations.remove(scope: removed.client.operationRecoveryScope) }
        if removed.connection != nil { store.removeConnection(hostID: hostID) } else { store.remove(); store.disableLegacy() }
        host = links.first?.name ?? ""; publish()
        if links.isEmpty { enrollmentGeneration = UUID(); stopEnrollmentMonitor() }
    }
}

#if DEBUG
/// One entry of the test-only nearby list read from `CMUX_REMOTE_TEST_NEARBY_PATH`.
struct TestNearbyEntry: Decodable {
    let id: String
    let name: String
}
#endif

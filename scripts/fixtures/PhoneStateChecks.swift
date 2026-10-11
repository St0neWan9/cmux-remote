import Foundation
import CmuxRemoteCore
import CmuxRemoteClient

private actor FixtureEnrollment: DeviceEnrolling {
    nonisolated let request: SignedValue<EnrollmentRequest>
    private let delaySubmission: Bool
    private var submitContinuation: CheckedContinuation<EnrollmentStatus, any Error>?
    private var calls = 0
    nonisolated let started = AsyncStream<Void>.makeStream()
    nonisolated let statusCalls = AsyncStream<Int>.makeStream()
    init(request: SignedValue<EnrollmentRequest>, delaySubmission: Bool) { self.request = request; self.delaySubmission = delaySubmission }
    func submit() async throws -> EnrollmentStatus {
        if delaySubmission {
            return try await withCheckedThrowingContinuation { continuation in submitContinuation = continuation; started.continuation.yield(()) }
        }
        started.continuation.yield(()); return EnrollmentStatus(request: request.value, state: "pending")
    }
    func finishSubmission() { submitContinuation?.resume(throwing: URLError(.cancelled)); submitContinuation = nil }
    func status() async throws -> EnrollmentStatus {
        calls += 1; statusCalls.continuation.yield(calls)
        if calls == 1 { throw URLError(.networkConnectionLost) }
        return EnrollmentStatus(request: request.value, state: "pending")
    }
    func cancel() async throws {}
    nonisolated func close() {}
    nonisolated func connection(from status: EnrollmentStatus) throws -> AuthorizedConnection { throw BridgeError("not_approved", "Fixture is pending") }
}

@main struct PhoneStateChecks {
    @MainActor static func main() async throws {
        let crypto = IdentityCryptography(); let hostKey = crypto.generatePrivateKey(); let publicKey = try crypto.publicKey(privateKey: hostKey)
        let host = HostIdentity(id: try crypto.identityID(publicKey: publicKey), publicKey: publicKey, certificateSHA256: String(repeating: "a", count: 64), name: "Fixture")
        let bootstrap = try crypto.sign(EnrollmentBootstrap(host: host, endpoint: BridgeEndpoint(host: "localhost", port: 7740), workspaces: ["11111111-1111-1111-1111-111111111111"], windowID: UUID().uuidString, expiresAt: Int(Date().timeIntervalSince1970) + 300), domain: "bootstrap", privateKey: hostKey)
        let key = crypto.generatePrivateKey(); let devicePublicKey = try crypto.publicKey(privateKey: key)
        let request = try crypto.sign(EnrollmentRequest(hostID: host.id, windowID: bootstrap.value.windowID, requestID: UUID().uuidString, clientID: crypto.identityID(publicKey: devicePublicKey), clientPublicKey: devicePublicKey, clientName: "Fixture", clientKind: "iphone", nonce: UUID().uuidString, scope: ClientScope(workspaces: bootstrap.value.workspaces, capabilities: [.workspaceRead]), expiresAt: bootstrap.value.expiresAt), domain: "enrollment-request", privateKey: key)
        let qr = try EnrollmentLinkCodec().encode(bootstrap)
        var failures: [String] = []

        let suspended = FixtureEnrollment(request: request, delaySubmission: true)
        let idleTicks = AsyncStream<Void>.makeStream()
        let cancelling = AppModel(identityKey: { key }, makeEnrollment: { _, _, _ in suspended }, enrollmentTicks: { (idleTicks.stream, {}) })
        let submission = Task { @MainActor in await cancelling.enrollQR(qr) }
        var started = suspended.started.stream.makeAsyncIterator(); _ = await started.next()
        await cancelling.cancelEnrollment(); await suspended.finishSubmission(); await submission.value
        if cancelling.loading { failures.append("Cancel left submission loading") }

        let recovering = FixtureEnrollment(request: request, delaySubmission: false)
        let ticks = AsyncStream<Void>.makeStream()
        let pending = AppModel(identityKey: { key }, makeEnrollment: { _, _, _ in recovering }, enrollmentTicks: { (ticks.stream, {}) })
        await pending.enrollQR(qr)
        var calls = recovering.statusCalls.stream.makeAsyncIterator()
        ticks.continuation.yield(()); _ = await calls.next()
        ticks.continuation.yield(())
        let deadline = Task { try await ContinuousClock().sleep(for: .seconds(2)); recovering.statusCalls.continuation.finish() }
        let secondCall = await calls.next(); deadline.cancel(); pending.pauseEnrollment()
        if secondCall != 2 { failures.append("One transient status failure permanently stopped enrollment") }

        let client = RemoteClient(pairing: try PairingConfiguration(host: "localhost", port: 1, token: String(repeating: "0", count: 32), certificateSHA256: String(repeating: "0", count: 64)))
        defer { client.close() }
        let session = SessionDescriptor(id: "fixture", agent: "claude", title: "Fixture", cwd: nil, workspaceID: "workspace", surfaceID: "surface", state: "working")
        let conversation = ConversationModel(session: session, client: client)
        conversation.markInterrupted()
        var updated = session; updated.state = "idle"; conversation.updateSession(updated)
        updated.state = "working"; conversation.updateSession(updated)
        if !conversation.working { failures.append("An earlier interrupt suppressed a later desktop turn") }

        if !failures.isEmpty { print(failures.joined(separator: "\n")); exit(1) }
        print("Phone state: 3 behavioral checks passed (cancel, transient reconnect, next-turn stop).")
    }
}

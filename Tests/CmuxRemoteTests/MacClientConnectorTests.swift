import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteMac

private actor ConnectorOwnerFixture: CmuxControlling {
    let host: HostIdentity
    let advertised: Bool
    var saved: Bool
    let enrollmentState: String?
    let enrollmentError: String
    var submissions = 0
    var resolutions = 0
    var submittedEndpoint: JSONValue = .null
    init(advertised: Bool, saved: Bool, enrollmentState: String? = nil, enrollmentError: String = "enrollment_pending") throws {
        let crypto = IdentityCryptography(), key = try crypto.publicKey(privateKey: crypto.generatePrivateKey())
        host = HostIdentity(id: try crypto.identityID(publicKey: key), publicKey: key, certificateSHA256: String(repeating: "b", count: 64), name: "Fixture")
        self.advertised = advertised; self.saved = saved
        self.enrollmentState = enrollmentState; self.enrollmentError = enrollmentError
    }
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        switch method {
        case "mac.connections":
            return .array(saved ? [.object(["id": .string(host.id), "host": try json(host),
                "endpoint": try json(BridgeEndpoint(host: "127.0.0.1", port: 7742))])] : [])
        case "mac.discovery.list":
            return try json(advertised ? [MacDiscoveredHost(host: host, serviceName: "fixture", serviceType: "_cmux-remote._tcp", serviceDomain: "local.")] : [])
        case "mac.discovery.resolve":
            resolutions += 1; return try json(BridgeEndpoint(host: "192.168.1.44", port: 7742))
        case "mac.enrollment.start":
            submissions += 1; submittedEndpoint = params["endpoint"] ?? .null
            #expect(params["host"]?["id"].string == host.id); #expect(params["trust_confirmed"]?.bool == true)
            return .object(["state": .string(saved ? "connected" : "pending")])
        case "mac.enrollment.status":
            guard let enrollmentState else { throw BridgeError(enrollmentError, "Fixture enrollment state is unavailable.") }
            if enrollmentState == "approved" { saved = true }
            return .object(["state": .string(enrollmentState)])
        default: throw BridgeError("not_found", "fixture")
        }
    }
    private func json<T: Encodable>(_ value: T) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) }
}

@Suite struct MacClientConnectorTests {
    @Test func statusIncludesConnectionSavedByThisApprovalPoll() async throws {
        let owner = try ConnectorOwnerFixture(advertised: false, saved: false, enrollmentState: "approved")
        let status = try await MacClientConnector(owner: owner).status()
        #expect(status["enrollment"]["state"].string == "approved")
        #expect(status["connections"].array?.count == 1)
    }
    @Test func statusReportsPendingAndDoesNotHideOwnerFailures() async throws {
        let pending = try ConnectorOwnerFixture(advertised: false, saved: false, enrollmentState: "pending")
        #expect(try await MacClientConnector(owner: pending).status()["enrollment"]["state"].string == "pending")
        let failed = try ConnectorOwnerFixture(advertised: false, saved: false, enrollmentError: "socket_unavailable")
        do { _ = try await MacClientConnector(owner: failed).status(); Issue.record("Owner failure was hidden") }
        catch let error as BridgeError { #expect(error.code == "socket_unavailable") }
    }
    @Test func statusWithSavedConnectionsAndNoEnrollmentIsANormalState() async throws {
        let owner = try ConnectorOwnerFixture(advertised: false, saved: true)
        let status = try await MacClientConnector(owner: owner).status()
        #expect(status["enrollment"]["state"].string == "idle")
        #expect(status["connections"].array?.count == 1)
        #expect(status["connections"].array?.first?["id"].string == owner.host.id)
        #expect(await owner.submissions == 0)
    }
    @Test func firstUseCannotRequestAccessWithoutExactCertificateConfirmation() async throws {
        let owner = try ConnectorOwnerFixture(advertised: true, saved: false)
        let connector = MacClientConnector(owner: owner)
        for fingerprint in [nil, String(repeating: "a", count: 64)] as [String?] {
            await #expect(throws: BridgeError.self) {
                _ = try await connector.connect(hostID: owner.host.id, confirmedCertificate: fingerprint, clientName: "Test Mac")
            }
        }
        #expect(await owner.submissions == 0); #expect(await owner.resolutions == 0)
        let state = try await connector.connect(hostID: owner.host.id, confirmedCertificate: owner.host.certificateSHA256, clientName: "Test Mac")
        #expect(state["state"].string == "pending"); #expect(await owner.submissions == 1)
    }
    @Test func savedHostCanRestoreWithoutDiscoveryOrAnotherTrustPrompt() async throws {
        let owner = try ConnectorOwnerFixture(advertised: false, saved: true)
        let state = try await MacClientConnector(owner: owner).connect(hostID: owner.host.id, confirmedCertificate: nil, clientName: "Test Mac")
        #expect(state["state"].string == "connected"); #expect(await owner.resolutions == 0)
        #expect(await owner.submittedEndpoint["host"].string == "127.0.0.1")
    }
    @Test func unknownHostNeverUsesAnArbitraryEndpoint() async throws {
        let owner = try ConnectorOwnerFixture(advertised: false, saved: false)
        await #expect(throws: BridgeError.self) {
            _ = try await MacClientConnector(owner: owner).connect(hostID: owner.host.id, confirmedCertificate: owner.host.certificateSHA256, clientName: "Test Mac")
        }
        #expect(await owner.submissions == 0); #expect(await owner.resolutions == 0)
    }
}

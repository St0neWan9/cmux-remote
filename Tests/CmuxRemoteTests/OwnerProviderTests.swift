import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteClient
@testable import CmuxRemoteBridge

private actor OwnerFixtureProvider: TerminalProvider {
    let descriptor: ProviderDescriptor
    let space: SpaceDescriptor
    let terminal: TerminalDescriptor
    private(set) var sent: [TerminalInputRequest] = []

    init() {
        let providerID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        descriptor = ProviderDescriptor(id: providerID, kind: .demo, name: "Fixture", hostName: "test",
                                        capabilities: [.spaces, .terminals, .screen, .input])
        space = SpaceDescriptor(id: "22222222-2222-4222-8222-222222222222", providerID: providerID,
                                title: "Fixture space", kind: "session")
        terminal = TerminalDescriptor(id: "33333333-3333-4333-8333-333333333333", providerID: providerID,
                                      spaceID: space.id, title: "shell", state: "running")
    }
    func spaces() async throws -> [SpaceDescriptor] { [space] }
    func terminals(spaceID: String) async throws -> [TerminalDescriptor] { spaceID == space.id ? [terminal] : [] }
    func layout(spaceID: String) async throws -> LayoutSnapshot {
        LayoutSnapshot(providerID: descriptor.id, spaceID: spaceID, revision: "1",
                       nodes: [LayoutNode(id: terminal.id, kind: "terminal", terminalID: terminal.id)])
    }
    func terminal(_ id: String) async throws -> TerminalDescriptor {
        guard id == terminal.id else { throw BridgeError("terminal_not_found", "Unknown terminal.", status: 404) }
        return terminal
    }
    func snapshot(terminalID: String) async throws -> TerminalSnapshot {
        TerminalSnapshot(providerID: descriptor.id, spaceID: space.id, terminalID: terminal.id,
                         revision: "1", columns: 80, rows: 24, format: "text", text: "screen")
    }
    func send(_ input: TerminalInputRequest, clientID: String, terminalID: String,
              authorize: @Sendable () async throws -> Void) async throws -> MutationReceipt {
        try await authorize()
        sent.append(input)
        return MutationReceipt(operationID: input.operationID, accepted: true)
    }
}

private struct WorkspaceListFixture: CmuxControlling {
    let rows: [JSONValue]
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue {
        guard method == "workspace.list" else { throw BridgeError("unsupported", "Fixture only lists workspaces.") }
        return .object(["workspaces": .array(rows)])
    }
}

@Suite struct OwnerProviderTests {
    /// A closed daemon workspace stays in the phone's history but must never be offered to a new device,
    /// and every cmux row names its source so mixed lists label both kinds the same way.
    @Test func ownerOmitsClosedWorkspacesAndLabelsCmuxRows() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = BridgeState(directory: root); try state.initialize()
        let authority = try state.authority(name: "Owner fixture")
        let transcript = root.appendingPathComponent("demo.jsonl")
        try Data().write(to: transcript)
        let rows: [JSONValue] = [
            .object(["id": .string("11111111-1111-4111-8111-111111111111"), "title": .string("Open")]),
            .object(["id": .string("22222222-2222-4222-8222-222222222222"), "title": .string("Closed"),
                     "backend": .string("cmux-tui"), "live": .bool(false)]),
            .object(["id": .string("33333333-3333-4333-8333-333333333333"), "title": .string("Orphaned"),
                     "backend": .string("cmux-tui"), "live": .bool(true), "attached": .bool(false)])
        ]
        let service = SessionService(cmux: WorkspaceListFixture(rows: rows), home: root, transcriptRoots: [root])
        let owner = OwnerControlRouter(authority: authority, service: service)

        let listed = await owner.respond(.object(["id": .string("1"), "method": .string("bridge.workspaces"), "params": .object([:])]))
        let workspaces = listed["result"]["workspaces"].array ?? []
        #expect(workspaces.count == 1)
        #expect(workspaces.first?["title"].string == "Open")
        #expect(workspaces.first?["source"].string == "cmux")
    }

    @Test func ownerCommandsListAndDriveAProviderTerminal() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = BridgeState(directory: root); try state.initialize()
        let authority = try state.authority(name: "Owner fixture")
        let transcript = root.appendingPathComponent("demo.jsonl")
        try Data().write(to: transcript)
        let service = SessionService(cmux: DemoCmux(transcript: transcript.path, project: root.path),
                                     home: root, transcriptRoots: [root])
        let registry = ProviderRegistry()
        let provider = OwnerFixtureProvider()
        try await registry.register(provider)
        let router = OwnerControlRouter(authority: authority, service: service,
                                        providers: ProviderDirectory(registry: registry))

        let spaces = await router.respond(.object(["id": .string("1"), "method": .string("providers.spaces"), "params": .object([:])]))
        #expect(spaces["ok"].bool == true)
        #expect(spaces["result"]["spaces"].array?.first?["id"].string == "22222222-2222-4222-8222-222222222222")

        let terminals = await router.respond(.object(["id": .string("2"), "method": .string("providers.terminals"),
                                           "params": .object(["space": .string("22222222-2222-4222-8222-222222222222")])]))
        #expect(terminals["result"]["terminals"].array?.first?["id"].string == "33333333-3333-4333-8333-333333333333")

        let screen = await router.respond(.object(["id": .string("3"), "method": .string("providers.screen"),
                                        "params": .object(["terminal": .string("33333333-3333-4333-8333-333333333333")])]))
        #expect(screen["result"]["text"].string == "screen")

        let operation = UUID()
        let input = await router.respond(.object(["id": .string("4"), "method": .string("providers.input"),
                                       "params": .object(["terminal": .string("33333333-3333-4333-8333-333333333333"),
                                                          "text": .string("hello"), "submit": .bool(true),
                                                          "operation_id": .string(operation.uuidString)])]))
        #expect(input["result"]["accepted"].bool == true)
        #expect(await provider.sent.map(\.operationID) == [operation])
    }

    /// A provider space must be offered in the owner's pairing list and must
    /// survive approval validation, or a Rex session can never reach a phone.
    @Test func ownerSharesAndApprovesAProviderSpace() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let state = BridgeState(directory: root); try state.initialize()
        let authority = try state.authority(name: "Owner fixture")
        let transcript = root.appendingPathComponent("demo.jsonl")
        try Data().write(to: transcript)
        let service = SessionService(cmux: DemoCmux(transcript: transcript.path, project: root.path),
                                     home: root, transcriptRoots: [root])
        let registry = ProviderRegistry()
        let provider = OwnerFixtureProvider()
        try await registry.register(provider)
        let providers = ProviderDirectory(registry: registry)
        let owner = OwnerControlRouter(authority: authority, service: service, providers: providers)
        let sharing = ManagedSharingService(state: state, authority: authority,
                                            router: BridgeRouter(service: service, authority: authority, providers: providers),
                                            listen: "127.0.0.1", port: 0, advertise: false)
        let started = try await sharing.start(); let port = try #require(started["port"].int)
        defer { Task { _ = await sharing.stop() } }

        let listed = await owner.respond(.object(["id": .string("1"), "method": .string("bridge.workspaces"), "params": .object([:])]))
        let row = listed["result"]["workspaces"].array?.first { $0["id"].string == provider.space.id }
        #expect(row?["source"].string == "Fixture")

        let opened = await owner.respond(.object(["id": .string("2"), "method": .string("enrollment.open"),
            "params": .object(["host": .string("127.0.0.1"), "port": .number(Double(port)),
                               "workspaces": .array([.string(provider.space.id)])])]))
        #expect(opened["ok"].bool == true)
        let bootstrap = try JSONDecoder().decode(SignedValue<EnrollmentBootstrap>.self,
                                                 from: JSONEncoder().encode(opened["result"]))
        let enrollment = try EnrollmentClient(bootstrap: bootstrap, privateKey: IdentityCryptography().generatePrivateKey(),
                                              name: "Fixture phone", kind: "iphone", capabilities: [.workspaceRead])
        defer { enrollment.close() }
        _ = try await enrollment.submit()
        let request = try #require(try await authority.pendingRequests().first)

        let scope = ClientScope(workspaces: [provider.space.id], capabilities: [.workspaceRead])
        let approved = await owner.respond(.object(["id": .string("3"), "method": .string("enrollment.approve"),
            "params": .object(["request_id": .string(request.requestID),
                               "scope": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(scope))])]))
        #expect(approved["ok"].bool == true, "\(approved)")
        #expect(try await authority.enrolledClients().first?.scope.workspaces == [provider.space.id])
    }
}

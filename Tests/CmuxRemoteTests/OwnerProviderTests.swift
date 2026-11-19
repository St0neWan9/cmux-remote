import Foundation
import Testing
import CmuxRemoteCore
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

@Suite struct OwnerProviderTests {
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
}

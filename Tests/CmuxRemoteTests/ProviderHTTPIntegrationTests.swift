import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge
import CmuxRemoteClient

private actor V3Provider: TerminalProvider {
    let descriptor: ProviderDescriptor
    let space: SpaceDescriptor
    let terminal: TerminalDescriptor
    private(set) var sent: [TerminalInputRequest] = []

    init(spaceID: String, terminalID: String) {
        let providerID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        descriptor = ProviderDescriptor(id: providerID, kind: .demo, name: "Fixture", hostName: "test",
                                        capabilities: [.spaces, .layout, .terminals, .screen, .input])
        space = SpaceDescriptor(id: spaceID, providerID: providerID, title: "Fixture space", kind: "session")
        terminal = TerminalDescriptor(id: terminalID, providerID: providerID, spaceID: spaceID,
                                      title: "shell", state: "running")
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

@Suite struct ProviderHTTPIntegrationTests {
    private static let spaceID = "22222222-2222-4222-8222-222222222222"
    private static let terminalID = "33333333-3333-4333-8333-333333333333"

    @Test(.timeLimit(.minutes(1)))
    func v3ResourcesAreScopedToTheGrantedSpace() async throws {
        let registry = ProviderRegistry()
        try await registry.register(V3Provider(spaceID: Self.spaceID, terminalID: Self.terminalID))
        let fixture = try await LinkIntegrationFixture.create(
            workspaces: [Self.spaceID], capabilities: [.workspaceRead, .terminalRead, .terminalInput],
            providers: ProviderDirectory(registry: registry))
        do {
            let client = try RemoteClient(connection: fixture.connection); defer { client.close() }
            let providers = try await client.get("/v3/providers", as: [ProviderDescriptor].self)
            #expect(providers.map(\.kind) == [.demo])
            let spaces = try await client.get("/v3/spaces", as: SpaceList.self)
            #expect(spaces.spaces.map(\.id) == [Self.spaceID])
            let terminals = try await client.get("/v3/spaces/\(Self.spaceID)/terminals", as: TerminalList.self)
            #expect(terminals.terminals.map(\.id) == [Self.terminalID])
            let snapshot = try await client.get("/v3/terminals/\(Self.terminalID)/screen", as: TerminalSnapshot.self)
            #expect(snapshot.text == "screen")
            let operation = UUID()
            let receipt = try await client.post("/v3/terminals/\(Self.terminalID)/input",
                                                body: TerminalInputRequest(text: "hi", submit: true, operationID: operation),
                                                as: MutationReceipt.self)
            #expect(receipt.operationID == operation)
            await fixture.stop()
        } catch {
            await fixture.stop()
            throw error
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func v3ScreenRequiresTerminalReadOnThatSpace() async throws {
        let registry = ProviderRegistry()
        try await registry.register(V3Provider(spaceID: Self.spaceID, terminalID: Self.terminalID))
        let fixture = try await LinkIntegrationFixture.create(
            workspaces: [Self.spaceID], capabilities: [.workspaceRead],
            providers: ProviderDirectory(registry: registry))
        do {
            let client = try RemoteClient(connection: fixture.connection); defer { client.close() }
            do {
                _ = try await client.get("/v3/terminals/\(Self.terminalID)/screen", as: TerminalSnapshot.self)
                Issue.record("A device without terminalRead must not read a screen")
            } catch let error as BridgeError {
                #expect(error.code == "scope_denied")
            }
            await fixture.stop()
        } catch {
            await fixture.stop()
            throw error
        }
    }
}

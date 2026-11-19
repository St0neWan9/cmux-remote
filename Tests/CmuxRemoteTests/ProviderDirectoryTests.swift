import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

private actor FixtureProvider: TerminalProvider {
    let descriptor: ProviderDescriptor
    let space: SpaceDescriptor
    let terminal: TerminalDescriptor
    var failSpaces = false
    var receipt: MutationReceipt?
    private(set) var sent: [TerminalInputRequest] = []

    init(id: String = UUID().uuidString, name: String = "fixture", failSpaces: Bool = false) {
        let providerID = id.lowercased()
        let spaceID = UUID().uuidString.lowercased()
        descriptor = ProviderDescriptor(id: providerID, kind: .demo, name: name, hostName: "test",
                                        capabilities: [.spaces, .terminals, .screen, .input])
        space = SpaceDescriptor(id: spaceID, providerID: providerID, title: "space", kind: "session")
        terminal = TerminalDescriptor(id: UUID().uuidString.lowercased(), providerID: providerID, spaceID: spaceID,
                                      title: "shell", state: "running")
        self.failSpaces = failSpaces
    }

    func setFailSpaces(_ value: Bool) { failSpaces = value }
    func setReceipt(_ value: MutationReceipt) { receipt = value }

    func spaces() async throws -> [SpaceDescriptor] {
        if failSpaces { throw BridgeError("fixture_down", "The fixture is down.", status: 503) }
        return [space]
    }
    func terminals(spaceID: String) async throws -> [TerminalDescriptor] {
        spaceID == space.id ? [terminal] : []
    }
    func layout(spaceID: String) async throws -> LayoutSnapshot {
        LayoutSnapshot(providerID: descriptor.id, spaceID: spaceID, revision: "1",
                       nodes: [LayoutNode(id: terminal.id, kind: "terminal", terminalID: terminal.id)])
    }
    func terminal(_ id: String) async throws -> TerminalDescriptor {
        guard id.lowercased() == terminal.id else { throw BridgeError("terminal_not_found", "Unknown terminal.", status: 404) }
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
        return receipt ?? MutationReceipt(operationID: input.operationID, accepted: true)
    }
}

@Suite struct ProviderDirectoryTests {
    private func directory(_ providers: [FixtureProvider]) async throws -> ProviderDirectory {
        let registry = ProviderRegistry()
        for provider in providers { try await registry.register(provider) }
        return ProviderDirectory(registry: registry)
    }

    @Test func listsSpacesAndResolvesTerminalScreen() async throws {
        let provider = FixtureProvider()
        let spaceID = provider.space.id
        let terminalID = provider.terminal.id
        let directory = try await directory([provider])
        let spaces = try await directory.spaces(providerID: nil)
        #expect(spaces.spaces.map(\.id) == [spaceID])
        let terminals = try await directory.terminals(spaceID: spaceID)
        #expect(terminals.terminals.map(\.id) == [terminalID])
        let snapshot = try await directory.snapshot(terminalID: terminalID)
        #expect(snapshot.text == "screen")
        #expect(try await directory.spaceID(forTerminal: terminalID) == spaceID)
    }

    @Test func rejectsUnknownProviderAndTerminal() async throws {
        let directory = try await directory([FixtureProvider()])
        await #expect(throws: BridgeError.self) {
            _ = try await directory.spaces(providerID: UUID().uuidString)
        }
        await #expect(throws: BridgeError.self) {
            _ = try await directory.snapshot(terminalID: UUID().uuidString)
        }
    }

    @Test func inputIsPassedThroughWithItsOperationIdentity() async throws {
        let provider = FixtureProvider()
        let terminalID = provider.terminal.id
        let directory = try await directory([provider])
        let operation = UUID()
        let receipt = try await directory.send(terminalID: terminalID,
                                               request: TerminalInputRequest(text: "echo hi", submit: true, operationID: operation),
                                               clientID: "device", authorize: {})
        #expect(receipt.operationID == operation)
        let sent = await provider.sent
        #expect(sent.map(\.operationID) == [operation])
    }

    @Test func aDifferentReceiptIdentityIsOutcomeUnknown() async throws {
        let provider = FixtureProvider()
        let terminalID = provider.terminal.id
        await provider.setReceipt(MutationReceipt(operationID: UUID(), accepted: true))
        let directory = try await directory([provider])
        await #expect(throws: BridgeError.self) {
            _ = try await directory.send(terminalID: terminalID,
                                         request: TerminalInputRequest(text: "x", operationID: UUID()),
                                         clientID: "device", authorize: {})
        }
    }

    @Test func refusedAuthorizationNeverReachesTheProvider() async throws {
        let provider = FixtureProvider()
        let terminalID = provider.terminal.id
        let directory = try await directory([provider])
        await #expect(throws: BridgeError.self) {
            _ = try await directory.send(terminalID: terminalID,
                                         request: TerminalInputRequest(text: "x", operationID: UUID()),
                                         clientID: "device", authorize: { throw BridgeError("scope_denied", "no", status: 403) })
        }
        let sent = await provider.sent
        #expect(sent.isEmpty)
    }

    @Test func oneFailingProviderDoesNotHideAnother() async throws {
        let down = FixtureProvider(name: "down", failSpaces: true)
        let up = FixtureProvider(name: "up")
        let upSpaceID = up.space.id
        let directory = try await directory([down, up])
        let list = try await directory.spaces(providerID: nil)
        #expect(list.spaces.map(\.id) == [upSpaceID])
        #expect(list.providerErrors == ["fixture_down"])
    }

    @Test func duplicateProviderIdentityIsRefused() async throws {
        let id = UUID().uuidString
        let registry = ProviderRegistry()
        try await registry.register(FixtureProvider(id: id))
        await #expect(throws: BridgeError.self) { try await registry.register(FixtureProvider(id: id)) }
    }

    @Test func inputIsBounded() async throws {
        let provider = FixtureProvider()
        let terminalID = provider.terminal.id
        let directory = try await directory([provider])
        await #expect(throws: BridgeError.self) {
            _ = try await directory.send(terminalID: terminalID,
                                         request: TerminalInputRequest(text: String(repeating: "a", count: 16_385), operationID: UUID()),
                                         clientID: "device", authorize: {})
        }
    }
}

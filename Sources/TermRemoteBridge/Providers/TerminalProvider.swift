import TermRemoteCore

/// One terminal backend behind the Bridge. Providers do not perform device
/// authorization; the directory and router do. They do own their idempotency
/// semantics for writes and return only a receipt they can prove.
public protocol TerminalProvider: Sendable {
    var descriptor: ProviderDescriptor { get async }
    func spaces() async throws -> [SpaceDescriptor]
    func terminals(spaceID: String) async throws -> [TerminalDescriptor]
    func layout(spaceID: String) async throws -> LayoutSnapshot
    func terminal(_ id: String) async throws -> TerminalDescriptor
    func snapshot(terminalID: String) async throws -> TerminalSnapshot
    func send(_ input: TerminalInputRequest, clientID: String, terminalID: String,
              authorize: @Sendable () async throws -> Void) async throws -> MutationReceipt
}

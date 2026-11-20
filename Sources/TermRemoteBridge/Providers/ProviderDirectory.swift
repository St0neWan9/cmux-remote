import Foundation
import TermRemoteCore

/// Resolves generic resource UUIDs to provider resources. The directory never
/// accepts a provider method, native id or endpoint from a caller, and it does
/// not perform device authorization; the router does that before calling it.
public actor ProviderDirectory {
    public static let maximumSpaces = 256
    public static let maximumTerminals = 256
    public static let maximumInputBytes = 16_384
    public static let maximumScreenBytes = 1_048_576

    private let registry: ProviderRegistry

    public init(registry: ProviderRegistry) { self.registry = registry }

    public func descriptors() async -> [ProviderDescriptor] { await registry.descriptors() }

    public func descriptor(providerID: String) async -> ProviderDescriptor? {
        await registry.provider(id: providerID)?.descriptor
    }

    public func spaces(providerID: String?) async throws -> SpaceList {
        let selected: [any TerminalProvider]
        if let providerID {
            guard let provider = await registry.provider(id: providerID) else {
                throw BridgeError("provider_not_found", "This terminal source is not available.", status: 404)
            }
            selected = [provider]
        } else { selected = await registry.all() }
        var spaces: [SpaceDescriptor] = []
        var errors: [String] = []
        for provider in selected {
            do {
                let items = try await provider.spaces()
                guard items.count <= Self.maximumSpaces else {
                    throw BridgeError("provider_invalid", "A provider returned too many spaces.", status: 502)
                }
                spaces += items
            } catch {
                errors.append(Self.code(error))
                if selected.count == 1, let failure = error as? BridgeError { throw failure }
            }
        }
        guard !spaces.isEmpty || errors.isEmpty else {
            throw BridgeError("provider_unavailable", "No terminal source is available.", status: 503)
        }
        return SpaceList(spaces: spaces, providerErrors: Array(Set(errors)).sorted())
    }

    public func terminals(spaceID: String) async throws -> TerminalList {
        let (provider, _) = try await resolveSpace(spaceID)
        let expected = await provider.descriptor.id
        let items = try await provider.terminals(spaceID: spaceID)
        guard items.count <= Self.maximumTerminals, items.allSatisfy({ $0.spaceID == spaceID && $0.providerID == expected }) else {
            throw BridgeError("provider_invalid", "A provider returned an invalid terminal listing.", status: 502)
        }
        return TerminalList(terminals: items)
    }

    public func layout(spaceID: String) async throws -> LayoutSnapshot {
        let (provider, _) = try await resolveSpace(spaceID)
        let expected = await provider.descriptor.id
        let value = try await provider.layout(spaceID: spaceID)
        guard value.spaceID == spaceID, value.providerID == expected, value.nodes.count <= Self.maximumTerminals * 4 else {
            throw BridgeError("provider_invalid", "A provider returned an invalid layout.", status: 502)
        }
        return value
    }

    public func snapshot(terminalID: String) async throws -> TerminalSnapshot {
        let (provider, terminal) = try await resolveTerminal(terminalID)
        let value = try await provider.snapshot(terminalID: terminal.id)
        guard value.terminalID == terminal.id, value.spaceID == terminal.spaceID,
              value.text.utf8.count <= Self.maximumScreenBytes, (value.vt?.count ?? 0) <= Self.maximumScreenBytes,
              value.columns >= 0, value.columns <= 10_000, value.rows >= 0, value.rows <= 10_000 else {
            throw BridgeError("provider_invalid", "A provider returned an invalid terminal screen.", status: 502)
        }
        return value
    }

    public func send(terminalID: String, request: TerminalInputRequest, clientID: String,
                     authorize: @Sendable () async throws -> Void) async throws -> MutationReceipt {
        guard !request.text.isEmpty || request.submit == true, request.text.utf8.count <= Self.maximumInputBytes else {
            throw BridgeError("invalid_input", "Terminal input must be non-empty and bounded.", status: 400)
        }
        let (provider, terminal) = try await resolveTerminal(terminalID)
        let receipt: MutationReceipt
        do { receipt = try await provider.send(request, clientID: clientID, terminalID: terminal.id, authorize: authorize) }
        catch let failure as BridgeError { throw failure }
        catch { throw BridgeError("outcome_unknown", "The terminal input outcome is unknown; it was not retried.", status: 409) }
        guard receipt.operationID == request.operationID, receipt.accepted else {
            throw BridgeError("outcome_unknown", "The terminal input outcome is unknown; it was not retried.", status: 409)
        }
        return receipt
    }

    /// The space a terminal belongs to, for capability checks before a read or write.
    public func spaceID(forTerminal terminalID: String) async throws -> String {
        try await resolveTerminal(terminalID).1.spaceID
    }

    public func terminalDetails(_ terminalID: String) async throws -> TerminalDescriptor {
        try await resolveTerminal(terminalID).1
    }

    private func resolveSpace(_ id: String) async throws -> (any TerminalProvider, SpaceDescriptor) {
        guard UUID(uuidString: id) != nil else { throw BridgeError("space_not_found", "Unknown space.", status: 404) }
        for provider in await registry.all() {
            guard let spaces = try? await provider.spaces(),
                  let space = spaces.first(where: { $0.id.lowercased() == id.lowercased() }) else { continue }
            return (provider, space)
        }
        throw BridgeError("space_not_found", "Unknown space.", status: 404)
    }

    private func resolveTerminal(_ id: String) async throws -> (any TerminalProvider, TerminalDescriptor) {
        guard UUID(uuidString: id) != nil else { throw BridgeError("terminal_not_found", "Unknown terminal.", status: 404) }
        for provider in await registry.all() {
            guard let terminal = try? await provider.terminal(id.lowercased()) else { continue }
            return (provider, terminal)
        }
        throw BridgeError("terminal_not_found", "Unknown terminal.", status: 404)
    }

    private static func code(_ error: any Error) -> String {
        if let failure = error as? BridgeError { return failure.code }
        return "provider_error"
    }
}

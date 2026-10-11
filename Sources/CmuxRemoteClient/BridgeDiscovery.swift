import Foundation
@preconcurrency import Network
import CmuxRemoteCore

/// Shared Bonjour browsing and bounded endpoint resolution for both client kinds.
@MainActor public final class BridgeDiscovery {
    private var browser: NWBrowser?
    public init() {}
    public func start() -> AsyncStream<[DiscoveredBridge]> {
        stop()
        let stream = AsyncStream<[DiscoveredBridge]>.makeStream(bufferingPolicy: .bufferingNewest(1))
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: "_cmux-remote._tcp", domain: "local."), using: .tcp)
        browser.browseResultsChangedHandler = { results, _ in
            let discovered = results.compactMap { result -> DiscoveredBridge? in
                guard case .bonjour(let txt) = result.metadata else { return nil }
                let fields = txt.dictionary
                guard fields["version"] == "2", let id = fields["hostID"], let key = fields["publicKey"], let certificate = fields["certificate"], let name = fields["name"] else { return nil }
                let host = HostIdentity(id: id, publicKey: key, certificateSHA256: certificate, name: name)
                guard (try? IdentityCryptography().validate(host)) != nil else { return nil }
                return DiscoveredBridge(host: host, service: result.endpoint)
            }.sorted { $0.id < $1.id }
            stream.continuation.yield(Array(discovered.prefix(64)))
        }
        browser.stateUpdateHandler = { state in
            if case .failed = state { stream.continuation.finish() }
            if case .cancelled = state { stream.continuation.finish() }
        }
        stream.continuation.onTermination = { _ in browser.cancel() }
        self.browser = browser; browser.start(queue: .main); return stream.stream
    }
    public func stop() { browser?.cancel(); browser = nil }
    public func resolve(_ discovered: DiscoveredBridge) async throws -> BridgeEndpoint {
        let stream = AsyncThrowingStream<BridgeEndpoint, any Error>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let connection = NWConnection(to: discovered.service, using: .tcp)
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                do {
                    let endpoint = try BonjourEndpointResolver().resolve(connection.currentPath?.remoteEndpoint)
                    stream.continuation.yield(endpoint); stream.continuation.finish()
                } catch { stream.continuation.finish(throwing: error) }
            case .failed: stream.continuation.finish(throwing: BridgeError("discovery_failed", "The service is not reachable."))
            case .cancelled: stream.continuation.finish(throwing: CancellationError())
            default: break
            }
        }
        // This is a connection deadline, not synchronization/polling.
        let timeout = Task { try await ContinuousClock().sleep(for: .seconds(8)); stream.continuation.finish(throwing: BridgeError("discovery_failed", "Service resolution timed out.")) }
        defer { timeout.cancel(); connection.cancel() }
        connection.start(queue: .main)
        return try await withTaskCancellationHandler {
            var iterator = stream.stream.makeAsyncIterator()
            guard let endpoint = try await iterator.next() else { throw BridgeError("discovery_failed", "No service endpoint is available.") }
            try endpoint.validate(); return endpoint
        } onCancel: { connection.cancel() }
    }
}

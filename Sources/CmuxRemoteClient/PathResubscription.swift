import Foundation
import CmuxRemoteCore

/// Keeps one path subscribed across link loss without ever dialing a link that is down.
///
/// Subscribing opens the link when it is closed, so a subscription that retried on a timer redialed an unreachable
/// Mac every half minute for as long as the app was open, and each failure also told its pages to read again,
/// which dialed once more. The phone's reconnect schedule already bounds automatic dials; a subscription whose
/// link went down therefore waits for that link to come back, from the schedule, a person's retry or a network
/// change, and only then subscribes and asks its pages to read. A failure on a working link keeps the backoff.
struct PathResubscription: Sendable {
    let subscribe: @Sendable (String) async throws -> AsyncThrowingStream<LinkFrame, any Error>
    /// Whether the link is down right now. Always false for a transport without link states.
    let linkDown: @Sendable () -> Bool
    /// Returns once the link is connected again, or when the caller is cancelled.
    let linkUp: @Sendable () async -> Void
    let discardEpoch: @Sendable () async -> Void
    let pause: @Sendable (Duration) async throws -> Void
    let trace: @Sendable (String) -> Void

    init(subscribe: @escaping @Sendable (String) async throws -> AsyncThrowingStream<LinkFrame, any Error>,
         linkDown: @escaping @Sendable () -> Bool, linkUp: @escaping @Sendable () async -> Void,
         discardEpoch: @escaping @Sendable () async -> Void = {},
         pause: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
         trace: @escaping @Sendable (String) -> Void = { _ in }) {
        self.subscribe = subscribe; self.linkDown = linkDown; self.linkUp = linkUp
        self.discardEpoch = discardEpoch; self.pause = pause; self.trace = trace
    }

    /// Watches `path` until cancelled or refused for good, calling `changed` for each invalidation.
    func run(_ path: String, changed: @escaping @Sendable () async -> Void) async {
        var attempt = 0
        while !Task.isCancelled {
            do {
                let subscription = try await subscribe(path)
                for try await _ in subscription { guard !Task.isCancelled else { return }; attempt = 0; await changed() }
            } catch {
                guard !Task.isCancelled else { return }
                let final = (error as? BridgeError).map { ["unauthorized", "scope_denied", "invalid_identity", "invalid_signature", "host_changed"].contains($0.code) } ?? false
                if final {
                    await changed()
                    trace("subscription ended \(path) error=\(TraceFormat().describe(error)) stopped"); return
                }
                if linkDown() {
                    // Reading now would only dial the dead link again; the pages read once it is back.
                    trace("subscription ended \(path) error=\(TraceFormat().describe(error)) waiting for the link")
                    await linkUp()
                    guard !Task.isCancelled else { return }
                    attempt = 0
                    await changed()
                    continue
                }
                await changed()
                trace("subscription ended \(path) error=\(TraceFormat().describe(error)) retry in \(1 << min(attempt + 1, 5))s")
                // The next subscribe must fetch the restarted Bridge's epoch, not sign with the old one again.
                if (error as? BridgeError)?.code == "invalid_proof" { await discardEpoch() }
            }
            attempt = min(attempt + 1, 5)
            // Reconnection backoff is an intended, cancellable delay.
            do { try await pause(.seconds(1 << attempt)) } catch { return }
        }
    }
}

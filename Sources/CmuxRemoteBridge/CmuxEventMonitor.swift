import Foundation
import CmuxRemoteCore

/// Reconnects the dedicated event reader with bounded backoff and snapshot recovery.
public actor CmuxEventMonitor {
    public typealias Consumer = @Sendable (Int?, @escaping @Sendable (JSONValue) async throws -> Void) async throws -> Void
    private let repository: CmuxEventCursorRepository
    private let consume: Consumer
    private let invalidate: @Sendable () async -> Void
    private let refresh: @Sendable () async throws -> Void
    private let accept: @Sendable (JSONValue) async -> Void
    private let wait: @Sendable (Duration) async throws -> Void
    private var cursor: CmuxEventCursor?
    private var acknowledged = false
    private var running = false
    public init(repository: CmuxEventCursorRepository, consume: @escaping Consumer,
                invalidate: @escaping @Sendable () async -> Void, refresh: @escaping @Sendable () async throws -> Void,
                accept: @escaping @Sendable (JSONValue) async -> Void,
                wait: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.repository = repository; self.consume = consume; self.invalidate = invalidate; self.refresh = refresh; self.accept = accept; self.wait = wait
    }
    public func run() async {
        guard !running else { return }; running = true; defer { running = false }
        cursor = try? await repository.load()
        var attempts = 0
        while !Task.isCancelled {
            acknowledged = false
            await invalidate()
            do {
                try await refresh(); try Task.checkCancellation()
                let after = cursor?.sequence
                try await consume(after) { [weak self] frame in
                    guard let self else { throw CancellationError() }; try await self.receive(frame)
                }
            } catch is CancellationError { break }
            catch { /* Snapshots remain the fallback; no mutation is retried. */ }
            await invalidate()
            if Task.isCancelled { break }
            attempts = acknowledged ? 0 : min(attempts + 1, 5)
            let delay = Duration.milliseconds(min(5000, 250 * (1 << attempts)))
            do { try await wait(delay) } catch { break }
        }
        await invalidate()
    }
    private func receive(_ frame: JSONValue) async throws {
        try Task.checkCancellation()
        guard let type = frame["type"].string else { throw BridgeError("event_resync", "Invalid event stream envelope.") }
        if type == "error" { throw BridgeError("event_resync", "The cmux event stream was rejected.") }
        guard let boot = frame["boot_id"].string, !boot.isEmpty, boot.utf8.count <= 128 else { throw BridgeError("event_resync", "The event boot identity is missing.") }
        if type == "ack" {
            guard let latest = frame["resume"]["latest_seq"].int, latest >= 0 else { throw BridgeError("event_resync", "Missing event resume baseline.") }
            let changedBoot = cursor.map { $0.bootID != boot } ?? false
            if changedBoot || frame["resume"]["gap"].bool == true || (cursor?.sequence ?? 0) > latest {
                cursor = nil; try await repository.save(nil); await invalidate()
                throw BridgeError("event_resync", "A boot change or replay gap requires a fresh snapshot.")
            }
            acknowledged = true
            if cursor == nil {
                // The live subscription is now established. Refresh afterwards
                // so events between initial snapshot and subscription cannot
                // disappear behind a newer resume baseline.
                try await refresh(); try Task.checkCancellation()
                let baseline = CmuxEventCursor(bootID: boot, sequence: latest)
                try await repository.save(baseline); cursor = baseline
            }
            await accept(frame); return
        }
        guard acknowledged, let previous = cursor, previous.bootID == boot else { throw BridgeError("event_resync", "Event arrived outside its acknowledged boot.") }
        guard let sequence = frame["seq"].int, sequence >= 0 else {
            if type == "heartbeat" { return }
            throw BridgeError("event_resync", "Event sequence is missing.")
        }
        // Category filters legitimately skip numbers. Only monotonicity applies.
        guard sequence > previous.sequence else { return }
        await accept(frame)
        try Task.checkCancellation()
        let next = CmuxEventCursor(bootID: boot, sequence: sequence)
        try await repository.save(next); cursor = next
    }
}

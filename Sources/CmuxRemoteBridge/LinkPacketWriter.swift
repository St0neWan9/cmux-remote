import Foundation
import CmuxRemoteCore

/// Serializes awaited sends in invocation order with an aggregate eight-MiB queue bound.
actor LinkPacketWriter {
    private struct Item {
        let data: Data
        let done: CheckedContinuation<Void, any Error>
    }
    private let send: @Sendable (Data) async throws -> Void
    private let packetLimit: Int
    private let terminate: @Sendable () -> Void
    private var cipher: LinkCipher?
    private var queue: [Item] = []
    private var bytes = 0
    private var running = false
    private var closed = false
    init(send: @escaping @Sendable (Data) async throws -> Void, terminate: @escaping @Sendable () -> Void, packetLimit: Int = 2_100_000) { self.send = send; self.terminate = terminate; self.packetLimit = packetLimit }
    func setCipher(_ value: LinkCipher) { cipher = value }
    func write(_ frame: LinkFrame) async throws {
        guard cipher != nil else { throw CancellationError() }
        let data = try cipher!.seal(frame); try await write(data)
    }
    func write(_ data: Data) async throws {
        guard !closed, data.count <= packetLimit, bytes + data.count <= 8_388_608, queue.count < 32 else { throw BridgeError("socket_unavailable", "The link send window is full or closed.", status: 503) }
        try await withCheckedThrowingContinuation { done in
            queue.append(Item(data: data, done: done)); bytes += data.count
            if !running { running = true; Task { await drain() } }
        }
    }
    func close() {
        guard !closed else { return }; closed = true; terminate()
        // The first item belongs to the current drain; fail only queued successors here.
        let retained = running && !queue.isEmpty ? 1 : 0
        for item in queue.dropFirst(retained) { item.done.resume(throwing: CancellationError()) }
        queue = Array(queue.prefix(retained)); bytes = queue.reduce(0) { $0 + $1.data.count }
    }
    private func drain() async {
        while let item = queue.first {
            do { try await send(item.data); item.done.resume() }
            catch { item.done.resume(throwing: error); close() }
            queue.removeFirst(); bytes -= item.data.count
            if closed { break }
        }
        running = false
    }
}

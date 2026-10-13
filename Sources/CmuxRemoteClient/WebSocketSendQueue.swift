import Foundation
import CmuxRemoteCore

/// Keeps ciphertext sends ordered even when requests arrive concurrently on the connection actor.
actor WebSocketSendQueue {
    private struct Item { let data: Data; let done: CheckedContinuation<Void, any Error> }
    private let socket: LinkSocket
    private var cipher: LinkCipher
    private var queue: [Item] = []
    private var bytes = 0
    private var running = false
    private var closed = false
    init(socket: LinkSocket, cipher: LinkCipher) { self.socket = socket; self.cipher = cipher }
    func send(_ frame: LinkFrame) async throws {
        let data = try cipher.seal(frame)
        guard !closed, queue.count < 32, bytes + data.count <= 8_388_608 else { throw BridgeError("socket_unavailable", "The link is closed or congested.", status: 503) }
        try await withCheckedThrowingContinuation { done in
            queue.append(Item(data: data, done: done)); bytes += data.count
            if !running { running = true; Task { await drain() } }
        }
    }
    func close() {
        guard !closed else { return }; closed = true; socket.close()
        let retained = running && !queue.isEmpty ? 1 : 0
        for item in queue.dropFirst(retained) { item.done.resume(throwing: CancellationError()) }
        queue = Array(queue.prefix(retained)); bytes = queue.reduce(0) { $0 + $1.data.count }
    }
    private func drain() async {
        while let item = queue.first {
            do { try await socket.send(item.data); item.done.resume() }
            catch { item.done.resume(throwing: error); close() }
            queue.removeFirst(); bytes -= item.data.count
            if closed { break }
        }
        running = false
    }
}

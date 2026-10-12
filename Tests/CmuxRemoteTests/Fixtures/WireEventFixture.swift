import Foundation
import CmuxRemoteCore
import CmuxRemoteBridge

/// Drives monitor recovery through the real socket framing and event transport.
actor WireEventFixture {
    let path: String
    var stages: [[JSONValue]]
    var subscriptions: [JSONValue] = []
    var accepted: [JSONValue] = []
    var invalidations = 0
    var refreshes = 0
    init(path: String, stages: [[JSONValue]]) { self.path = path; self.stages = stages }
    func consume(after: Int?, receive: @escaping @Sendable (JSONValue) async throws -> Void) async throws {
        guard !stages.isEmpty else { throw CancellationError() }
        let frames = stages.removeFirst()
        if FileManager.default.fileExists(atPath: path) { try FileManager.default.removeItem(atPath: path) }
        var data = Data()
        for frame in frames { data.append(try JSONEncoder().encode(frame)); data.append(10) }
        let fixture = try SocketResponseFixture(path: path, response: data)
        var failure: (any Error)?
        do { try await CmuxEventClient(path: path).consume(afterSequence: after, onFrame: receive) }
        catch { failure = error }
        let request = try await fixture.completion.value
        subscriptions.append(try JSONDecoder().decode(JSONValue.self, from: request))
        if let failure { throw failure }
    }
    func accept(_ frame: JSONValue) { accepted.append(frame) }
    func invalidate() { invalidations += 1 }
    func refresh() { refreshes += 1 }
    func wait(_ duration: Duration) throws { if stages.isEmpty { throw CancellationError() } }
}

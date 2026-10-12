import Foundation
import CmuxRemoteCore

actor EventMonitorFixture {
    var attempts: [Int?] = []
    var accepted: [JSONValue] = []
    var resets = 0
    var refreshes = 0
    var waits = 0
    let stages: [[JSONValue]]
    init(stages: [[JSONValue]]) { self.stages = stages }
    func consume(after: Int?, receive: @Sendable (JSONValue) async throws -> Void) async throws {
        let index = attempts.count; attempts.append(after)
        guard index < stages.count else { throw CancellationError() }
        for frame in stages[index] { try await receive(frame) }
    }
    func accept(_ frame: JSONValue) { accepted.append(frame) }
    func invalidate() { resets += 1 }
    func refresh() { refreshes += 1 }
    func wait(_ delay: Duration) throws {
        waits += 1
        if waits >= stages.count { throw CancellationError() }
    }
}

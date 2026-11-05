import Foundation
import Testing
import CmuxRemoteCore

@Suite struct SessionRecencyTests {
    private let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private func session(_ id: String, hoursAgo: Double?, state: String = "ended") -> SessionDescriptor {
        SessionDescriptor(id: id, agent: "claude", title: id, cwd: nil, state: state,
                          updatedAt: hoursAgo.map { now.addingTimeInterval(-$0 * 3600) })
    }
    @Test func aConversationActiveWithinThreeDaysStaysInView() {
        let recency = SessionRecency(now: now)
        #expect(recency.isRecent(session("a", hoursAgo: 71)))
        #expect(!recency.isRecent(session("b", hoursAgo: 73)))
        #expect(!recency.isRecent(session("c", hoursAgo: nil)), "A conversation with no recorded activity is history")
    }
    @Test func aRunningOrWaitingConversationNeverFoldsWhateverItsAge() {
        let recency = SessionRecency(now: now)
        #expect(recency.isRecent(session("w", hoursAgo: 500, state: "working")))
        #expect(recency.isRecent(session("q", hoursAgo: nil, state: "needs_input")))
    }
    @Test func aWorkspaceKeepsItsThreeNewestRowsEvenWhenAllAreOld() {
        let rows = (1...8).map { session("s\($0)", hoursAgo: Double(100 + $0)) }
        let split = SessionRecency(now: now).split(rows, floor: SessionRecency.workspaceFloor) { $0 }
        #expect(split.shown.map(\.id) == ["s1", "s2", "s3"])
        #expect(split.earlier.count == 5)
    }
    @Test func recentRowsPastTheFloorStayAndOnlyOldOnesFold() {
        let rows = [session("r1", hoursAgo: 1), session("r2", hoursAgo: 2), session("r3", hoursAgo: 3),
                    session("r4", hoursAgo: 4), session("old1", hoursAgo: 200), session("old2", hoursAgo: nil)]
        let split = SessionRecency(now: now).split(rows, floor: SessionRecency.workspaceFloor) { $0 }
        #expect(split.shown.map(\.id) == ["r1", "r2", "r3", "r4"])
        #expect(split.earlier.map(\.id) == ["old1", "old2"])
    }
    @Test func aRunningConversationBelowOlderRowsIsStillShown() {
        // The Bridge may report a live Agent without a time, which sorts it after every dated row.
        let rows = (1...7).map { session("old\($0)", hoursAgo: Double(100 + $0)) } + [session("live", hoursAgo: nil, state: "working")]
        let split = SessionRecency(now: now).split(rows, floor: SessionRecency.timeFloor) { $0 }
        #expect(split.shown.map(\.id) == ["old1", "old2", "old3", "old4", "old5", "old6", "live"])
        #expect(split.earlier.map(\.id) == ["old7"])
    }
    @Test func aShortListFoldsNothing() {
        let rows = [session("a", hoursAgo: 900), session("b", hoursAgo: 901)]
        let split = SessionRecency(now: now).split(rows, floor: SessionRecency.workspaceFloor) { $0 }
        #expect(split.earlier.isEmpty)
    }
}

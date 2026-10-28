import Testing
@testable import CmuxRemoteCore

@Suite struct ActivityGroupPolicyTests {
    @Test func theNewestSmallGroupOpens() {
        #expect(ActivityGroupPolicy.showsInline(operationCount: 0, isLatest: true, choice: nil))
        #expect(ActivityGroupPolicy.showsInline(operationCount: ActivityGroupPolicy.inlineLimit, isLatest: true, choice: nil))
    }
    /// A running Agent's group keeps growing; past the limit it stays summarised even while it is the newest.
    @Test func aGroupPastTheLimitStaysSummarised() {
        #expect(!ActivityGroupPolicy.showsInline(operationCount: ActivityGroupPolicy.inlineLimit + 1, isLatest: true, choice: nil))
        #expect(!ActivityGroupPolicy.showsInline(operationCount: 40, isLatest: true, choice: true))
    }
    @Test func anOlderGroupFollowsTheReadersChoice() {
        #expect(ActivityGroupPolicy.showsInline(operationCount: 2, isLatest: false, choice: true))
        #expect(!ActivityGroupPolicy.showsInline(operationCount: 2, isLatest: false, choice: nil))
    }
}

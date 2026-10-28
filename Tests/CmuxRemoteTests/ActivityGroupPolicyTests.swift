import Testing
@testable import CmuxRemoteCore

@Suite struct ActivityGroupPolicyTests {
    /// The running group stays open so its work can be followed; it stops being newest once the next one arrives.
    @Test func theNewestGroupStaysOpen() {
        #expect(ActivityGroupPolicy.isExpanded(isLatest: true, choice: nil))
        #expect(ActivityGroupPolicy.isExpanded(isLatest: true, choice: true))
        #expect(!ActivityGroupPolicy.isExpanded(isLatest: false, choice: nil))
        #expect(ActivityGroupPolicy.isExpanded(isLatest: false, choice: true))
    }
    /// Past the limit the group draws its newest slice instead of growing into one enormous row.
    @Test func aLongGroupDrawsOnlyItsNewestSlice() {
        #expect(ActivityGroupPolicy.drawsWhole(operationCount: 0))
        #expect(ActivityGroupPolicy.drawsWhole(operationCount: ActivityGroupPolicy.inlineLimit))
        #expect(!ActivityGroupPolicy.drawsWhole(operationCount: ActivityGroupPolicy.inlineLimit + 1))
        #expect(!ActivityGroupPolicy.drawsWhole(operationCount: 200))
    }
}

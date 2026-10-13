import Testing
@testable import CmuxRemoteBridge

@Suite struct LinkInputBudgetTests {
    @Test func burstsWithinCountAndByteBoundsAreAdmittedAndReleased() {
        let budget = LinkInputBudget(packetLimit: 3, byteLimit: 100)
        #expect(budget.admit(40)); #expect(budget.admit(40))
        #expect(!budget.admit(30), "Bytes beyond the bound must close the link")
        #expect(budget.admit(20))
        #expect(!budget.admit(0), "Packets beyond the bound must close the link")
        budget.release(40)
        #expect(budget.admit(10))
    }
}

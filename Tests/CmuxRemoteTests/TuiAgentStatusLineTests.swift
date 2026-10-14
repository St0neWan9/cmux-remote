import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// The agent's working line exists only on the rendered screen; these are the forms it prints.
@Suite struct TuiAgentStatusLineTests {
    @Test func readsTheGerundTimerAndTokenCount() {
        let status = TuiAgentStatusLine.parse(rows: ["⏺ Writing the summary.", "✻ Blanching… (54s · ↓ 2.3k tokens)", "❯"])
        #expect(status?.glyph == "✻")
        #expect(status?.activity == "Blanching…")
        #expect(status?.elapsedSeconds == 54)
        #expect(status?.tokenCount == "2.3k")
        #expect(status?.tokensAscending == false)
    }
    @Test func readsMinutesAndAnAscendingCount() {
        let status = TuiAgentStatusLine.parse(rows: ["✶ Cannoodling… (1m05s · ↑ 12.4k tokens)"])
        #expect(status?.activity == "Cannoodling…")
        #expect(status?.elapsedSeconds == 65)
        #expect(status?.tokenCount == "12.4k")
        #expect(status?.tokensAscending == true)
    }
    @Test func readsTheBareTimerFormUsedWhileRunningStopHooks() {
        let status = TuiAgentStatusLine.parse(rows: ["✻ Running stop hooks… 0/3 · 3s · ↓ 56 tokens"])
        #expect(status?.elapsedSeconds == 3)
        #expect(status?.tokenCount == "56")
    }
    @Test func readsABareWordCountWithoutAKSuffix() {
        let status = TuiAgentStatusLine.parse(rows: ["✳ Pondering… (7s · ↓ 560 tokens)"])
        #expect(status?.tokenCount == "560")
    }
    /// The gerund appears first; the timer follows a moment later, and the count later still.
    @Test func readsAGerundBeforeAnyTimerAppears() {
        let status = TuiAgentStatusLine.parse(rows: ["✻ Nebulizing…"])
        #expect(status?.activity == "Nebulizing…")
        #expect(status?.elapsedSeconds == nil)
        #expect(status?.tokenCount == nil)
    }
    /// A settled turn leaves `Brewed for 30s` behind, which is not a live line.
    @Test func aSettledSummaryIsNotAWorkingLine() {
        #expect(TuiAgentStatusLine.parse(rows: ["✻ Brewed for 30s"]) == nil)
    }
    @Test func prefersTheLowestWorkingLine() {
        // The mode bar sits below the input box and carries its own glyph; the working line wins.
        let status = TuiAgentStatusLine.parse(rows: ["✻ Thinking… (3s · ↓ 12 tokens)", "❯ ", "✻ auto mode on"])
        #expect(status?.elapsedSeconds == 3)
    }
    @Test func readsTheCompactingLineThatReplacesTheActivity() {
        let status = TuiAgentStatusLine.parse(rows: ["✻ Compacting… (1m12s · ↓ 4.1k tokens)"])
        #expect(status?.isCompacting == true)
        #expect(status?.activity == nil)
        #expect(status?.elapsedSeconds == 72)
        #expect(status?.tokenCount == "4.1k")
    }
    @Test func anOrdinaryActivityIsNotCompaction() {
        let status = TuiAgentStatusLine.parse(rows: ["✻ Blanching… (54s · ↓ 2.3k tokens)"])
        #expect(status?.isCompacting == false)
        #expect(status?.activity == "Blanching…")
    }

    @Test func aScreenWithNoWorkingLineHasNoStatus() {
        #expect(TuiAgentStatusLine.parse(rows: ["⏺ Done.", "❯ "]) == nil)
        #expect(TuiAgentStatusLine.parse(rows: []) == nil)
    }
}

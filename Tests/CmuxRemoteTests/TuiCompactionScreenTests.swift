import Foundation
import Testing
@testable import CmuxRemoteBridge

/// Compaction is printed on the agent's working line, which exists only on the rendered screen.
@Suite struct TuiCompactionScreenTests {
    @Test func readsTheCompactingLine() {
        #expect(TuiCompactionScreen.isCompacting(rows: ["✻ Compacting… (1m12s · ↓ 4.1k tokens)"]))
        #expect(TuiCompactionScreen.isCompacting(rows: ["⏺ Working.", "✻ Compacting context…"]))
    }
    @Test func anOrdinaryWorkingLineIsNotCompaction() {
        #expect(!TuiCompactionScreen.isCompacting(rows: ["✻ Blanching… (54s · ↓ 2.3k tokens)"]))
        #expect(!TuiCompactionScreen.isCompacting(rows: ["⏺ Done.", "❯ "]))
        #expect(!TuiCompactionScreen.isCompacting(rows: []))
    }
    /// Only an agent's own glyph-led row counts, so prose mentioning compaction is not a signal.
    @Test func proseAboutCompactionIsNotASignal() {
        #expect(!TuiCompactionScreen.isCompacting(rows: ["The context compaction finished earlier."]))
        #expect(!TuiCompactionScreen.isCompacting(rows: ["⏺ I ran compaction."]))
    }
}

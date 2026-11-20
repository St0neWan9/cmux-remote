import SwiftTerm

/// Decode-only delegate: never launches a process, forwards replies, or touches clipboard/UI.
final class TuiTerminalSink: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}
    func isProcessTrusted(source: Terminal) -> Bool { false }
}

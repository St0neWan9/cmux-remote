import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteMac

@Suite struct TerminalInputBufferTests {
    @Test func arrowRepeatCoalescesWithoutLosingBytesDuringASlowWrite() async throws {
        let input = TerminalInputBuffer()
        let arrow = Data("\u{1B}[A".utf8)
        for _ in 0..<275 { try input.append(arrow) }
        var iterator = input.notifications.makeAsyncIterator()
        #expect(try await iterator.next() != nil)
        #expect(try input.take() == Data(String(repeating: "\u{1B}[A", count: 275).utf8))
        let text = Data("输入验证👩‍💻".utf8)
        for byte in text { try input.append(Data([byte])) }
        #expect(try await iterator.next() != nil)
        #expect(try input.take() == text)
        input.finish()
        #expect(try await iterator.next() == nil)
    }
    @Test func overflowRejectsTheWholePendingBatchAndCannotRetryIt() throws {
        let input = TerminalInputBuffer(maximumBytes: 6)
        try input.append(Data("1234".utf8))
        do { try input.append(Data("567".utf8)); Issue.record("Expected bounded input") }
        catch { #expect((error as? BridgeError)?.code == "input_queue_full") }
        #expect(throws: BridgeError.self) { _ = try input.take() }
        #expect(throws: BridgeError.self) { try input.append(Data("again".utf8)) }
    }
    @Test func cancellationDiscardsPendingInputAndStopsNotificationWait() async throws {
        let input = TerminalInputBuffer()
        try input.append(Data("unsent".utf8))
        input.finish(throwing: CancellationError())
        #expect(throws: CancellationError.self) { _ = try input.take() }
        var iterator = input.notifications.makeAsyncIterator()
        do { while try await iterator.next() != nil {}; Issue.record("Expected cancellation") }
        catch { #expect(error is CancellationError) }
    }
}

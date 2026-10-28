import Foundation
import Testing
@testable import CmuxRemoteCore

/// The title the phone may write into cmux's tab model.
@Suite struct SessionTitleTests {
    @Test func trimsSurroundingSpaceAndKeepsTheRest() throws {
        #expect(try SessionTitle.validated("  Review the relay  ") == "Review the relay")
    }
    /// An empty title is the way to clear a custom name, so it must validate rather than fail.
    @Test func anEmptyTitleIsAllowed() throws {
        #expect(try SessionTitle.validated("   ").isEmpty)
    }
    @Test func refusesLineBreaksAndControlCharacters() {
        #expect(throws: BridgeError.self) { _ = try SessionTitle.validated("two\nlines") }
        #expect(throws: BridgeError.self) { _ = try SessionTitle.validated("bell\u{7}") }
    }
    @Test func refusesATitleBeyondItsBound() {
        #expect(try! SessionTitle.validated(String(repeating: "a", count: SessionTitle.limit)).count == SessionTitle.limit)
        #expect(throws: BridgeError.self) { _ = try SessionTitle.validated(String(repeating: "a", count: SessionTitle.limit + 1)) }
    }
}

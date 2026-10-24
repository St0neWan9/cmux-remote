import XCTest
import CmuxRemoteCore
@testable import CmuxRemote

/// A relay reconnect while the phone waits for the owner's approval must not end the wait.
final class EnrollmentPollRetryTests: XCTestCase {
    private let retry = EnrollmentPollRetry()
    func testALinkDroppedMidPollIsAskedAgain() {
        let lost = BridgeError("outcome_unknown", "Inspect the operation receipt before retrying.", status: 504)
        XCTAssertTrue(retry.shouldRetry(lost, expiresAt: 1_000, now: 900))
        XCTAssertTrue(retry.shouldRetry(BridgeError("socket_unavailable", "The link consumer timed out.", status: 504), expiresAt: 1_000, now: 900))
        XCTAssertTrue(retry.shouldRetry(URLError(.networkConnectionLost), expiresAt: 1_000, now: 900))
    }
    func testAnExpiredRequestStopsRetrying() {
        let lost = BridgeError("outcome_unknown", "Inspect the operation receipt before retrying.", status: 504)
        XCTAssertFalse(retry.shouldRetry(lost, expiresAt: 900, now: 900))
        XCTAssertFalse(retry.shouldRetry(lost, expiresAt: 800, now: 900))
    }
    func testARefusalIsNotRetried() {
        XCTAssertFalse(retry.shouldRetry(BridgeError("invalid_input", "Choose an exact request ID.", status: 400), expiresAt: 1_000, now: 900))
        XCTAssertFalse(retry.shouldRetry(URLError(.badServerResponse), expiresAt: 1_000, now: 900))
    }
}

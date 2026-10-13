import Foundation

/// One outbound relay WebSocket; tests substitute a scripted peer for the cloud.
public protocol CloudRelayConnecting: Sendable {
    func send(_ bytes: Data) async throws
    func receive() async throws -> Data
    func ping() async throws
    func failureCode() -> String
    func close()
}

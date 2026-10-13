import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

@Suite struct BridgeMachineLeaseTests {
    @Test func secondBridgeOnTheSameMacIsRefusedUntilTheFirstStops() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: home) }
        var first: BridgeMachineLease? = try BridgeMachineLease(home: home)
        do { _ = try BridgeMachineLease(home: home); Issue.record("A second Bridge must not start") }
        catch { #expect((error as? BridgeError)?.code == "bridge_already_running") }
        _ = first; first = nil
        _ = try BridgeMachineLease(home: home)
    }
}

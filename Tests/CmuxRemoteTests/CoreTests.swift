import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

@Suite struct CoreTests {
    @Test func pairingRejectsInvalidEndpoint() {
        #expect(throws: BridgeError.self) { try PairingConfiguration(host: "user@host", port: 7740, token: String(repeating: "a", count: 64), certificateSHA256: String(repeating: "b", count: 64)) }
    }
    @Test func jsonPreservesUnknownSnapshotFields() throws {
        let source = Data(#"{"unknown":[true,null,42,"value"]}"#.utf8)
        let value = try JSONDecoder().decode(JSONValue.self, from: source)
        #expect(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) == value)
    }
}

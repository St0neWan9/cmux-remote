import Testing
import CmuxRemoteCore

@Suite struct PairingLinkTests {
    @Test func qrRoundTripFillsEveryConnectionField() throws {
        let pairing = try PairingConfiguration(host: "192.168.1.8", port: 7740, token: String(repeating: "a", count: 64), certificateSHA256: String(repeating: "b", count: 64))
        let codec = PairingLinkCodec()
        #expect(try codec.decode(codec.encode(pairing)) == pairing)
    }
    @Test(arguments: ["https://example.com", "cmux-remote://pair?v=2&payload=abc", "cmux-remote://pair?v=1&payload=abc"])
    func unrelatedOrMalformedCodesNeverStartPairing(_ text: String) {
        #expect(throws: BridgeError.self) { try PairingLinkCodec().decode(text) }
    }
    @Test(arguments: ["[", ":", "%", "bad host", "host:7740", "host\nname"])
    func malformedEndpointsAreRejectedBeforeNetworking(_ host: String) {
        #expect(throws: BridgeError.self) { try PairingConfiguration(host: host, port: 7740, token: String(repeating: "a", count: 64), certificateSHA256: String(repeating: "b", count: 64)) }
    }
}

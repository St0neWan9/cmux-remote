import Foundation
import Testing
import TermRemoteCore
import TermRemoteBridge

@Suite struct RexEndpointTests {
    @Test func parsesTheSupportedEndpoints() throws {
        #expect(try RexEndpoint.parse("unix:/tmp/rex.sock") == .unix(path: "/tmp/rex.sock"))
        #expect(try RexEndpoint.parse("unix:///Users/me/Library/Application%20Support/rex/server.sock")
                == .unix(path: "/Users/me/Library/Application Support/rex/server.sock"))
        #expect(try RexEndpoint.parse("http://127.0.0.1:7297") == .tcp(host: "127.0.0.1", port: 7297, tls: false))
        #expect(try RexEndpoint.parse("https://rex.tailnet.ts.net") == .tcp(host: "rex.tailnet.ts.net", port: 443, tls: true))
        #expect(try RexEndpoint.parse("http://host") == .tcp(host: "host", port: 7297, tls: false))
    }

    @Test func rejectsUnsupportedOrMalformedEndpoints() {
        #expect(throws: BridgeError.self) { try RexEndpoint.parse("") }
        #expect(throws: BridgeError.self) { try RexEndpoint.parse("ssh://host") }
        #expect(throws: BridgeError.self) { try RexEndpoint.parse("http://host:0") }
        #expect(throws: BridgeError.self) { try RexEndpoint.parse("ftp://host") }
    }
}

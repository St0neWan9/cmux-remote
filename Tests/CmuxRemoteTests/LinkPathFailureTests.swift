import Foundation
import Darwin
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteClient

@Suite struct LinkPathFailureTests {
    @Test func unreachableLANFallsBackButIdentityAndTLSFailuresDoNot() {
        let path = LinkPathFailure()
        #expect(path.isUnreachable(URLError(.timedOut)))
        #expect(path.isUnreachable(NSError(domain: NSPOSIXErrorDomain, code: Int(ENETUNREACH))), "Cellular phones see an unreachable private LAN as an errno")
        #expect(path.isUnreachable(NSError(domain: NSPOSIXErrorDomain, code: Int(ENOTCONN))))
        #expect(path.isUnreachable(NSError(domain: NSPOSIXErrorDomain, code: Int(ECONNREFUSED))))
        #expect(!path.isUnreachable(URLError(.serverCertificateUntrusted)))
        #expect(!path.isUnreachable(URLError(.cancelled)), "A rejected certificate pin cancels the challenge and must not be masked by the relay")
        #expect(!path.isUnreachable(BridgeError("invalid_identity", "Host changed")))
        #expect(!path.isUnreachable(NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))))
    }
}

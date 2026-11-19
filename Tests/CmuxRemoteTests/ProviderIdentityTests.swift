import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

@Suite struct ProviderIdentityTests {
    @Test func derivedIdentifiersAreStableUUIDs() {
        let first = ProviderIdentity.providerID(kind: .rex, instance: "host-a")
        let second = ProviderIdentity.providerID(kind: .rex, instance: "host-a")
        #expect(first == second)
        #expect(first != ProviderIdentity.providerID(kind: .rex, instance: "host-b"))
        #expect(first != ProviderIdentity.providerID(kind: .cmuxDesktop, instance: "host-a"))
        #expect(!first.contains("host-a"))

        guard let uuid = UUID(uuidString: first) else { Issue.record("not a UUID"); return }
        let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }
        #expect(bytes[6] >> 4 == 0x8)
        #expect(bytes[8] & 0xC0 == 0x80)
    }

    @Test func resourceIdentifiersDoNotCollideAcrossProvidersOrKinds() {
        let provider = ProviderIdentity.providerID(kind: .rex, instance: "host-a")
        let session = ProviderIdentity.resourceID(providerID: provider, kind: "space", nativeID: "session:one")
        #expect(session == ProviderIdentity.resourceID(providerID: provider, kind: "space", nativeID: "session:one"))
        #expect(session != ProviderIdentity.resourceID(providerID: provider, kind: "terminal", nativeID: "session:one"))
        #expect(session != ProviderIdentity.resourceID(providerID: "different", kind: "space", nativeID: "session:one"))
        #expect(UUID(uuidString: session) != nil)
    }
}

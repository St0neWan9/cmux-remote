import Foundation
import CryptoKit
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

@Suite struct LinkCipherTests {
    private func fixture() async throws -> (LinkClientHandshake, SignedValue<LinkAcceptance>, LinkCipher) {
        let crypto = IdentityCryptography(), privateKey = crypto.generatePrivateKey()
        let publicKey = try crypto.publicKey(privateKey: privateKey)
        let host = HostIdentity(id: try crypto.identityID(publicKey: publicKey), publicKey: publicKey, certificateSHA256: String(repeating: "a", count: 64), name: "Fixture")
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let authority = try ConnectionAuthority(host: host, privateKey: privateKey, registryFile: file)
        let handshake = try LinkClientHandshake(host: host, privateKey: crypto.generatePrivateKey())
        let agreement = P256.KeyAgreement.PrivateKey()
        let acceptance = try await authority.acceptLink(handshake.proposal, key: agreement)
        let server = try LinkCipher(key: agreement, peerKey: handshake.proposal.value.agreementKey, proposal: handshake.proposal, acceptance: acceptance, server: true)
        return (handshake, acceptance, server)
    }
    @Test func orderedDuplexPayloadsAreAuthenticatedAndReplayFails() async throws {
        let (handshake, acceptance, serverValue) = try await fixture()
        var client = try handshake.accept(acceptance), server = serverValue
        let id = UUID().uuidString
        let first = try client.seal(LinkFrame(kind: "request", id: id, method: "GET", uri: "/v2/sessions"))
        #expect(try server.open(first).uri == "/v2/sessions")
        let next = try client.seal(LinkFrame(kind: "cancel", id: id))
        #expect(try server.open(next).kind == "cancel")
        let reply = try server.seal(LinkFrame(kind: "response", id: id, data: Data("private content".utf8), status: 200, index: 0, final: true))
        #expect(try client.open(reply).data == Data("private content".utf8))
        #expect(throws: (any Error).self) { try server.open(first) }
    }
    @Test func changedCiphertextAndCrossHandshakeReplyAreRejected() async throws {
        let (handshake, acceptance, serverValue) = try await fixture()
        var client = try handshake.accept(acceptance), server = serverValue
        let bytes = try client.seal(LinkFrame(kind: "request", id: UUID().uuidString, data: Data("private".utf8)))
        let packet = try JSONDecoder().decode(SealedLinkPacket.self, from: bytes)
        var corrupt = packet.ciphertext; corrupt[0] ^= 1
        let tampered = try JSONEncoder().encode(SealedLinkPacket(encapsulatedKey: packet.encapsulatedKey, ciphertext: corrupt))
        #expect(throws: (any Error).self) { try server.open(tampered) }
        let (other, _, _) = try await fixture()
        #expect(throws: (any Error).self) { try other.accept(acceptance) }
    }
    @Test func proposalExpiryAndIdentitySubstitutionFail() async throws {
        let (handshake, acceptance, _) = try await fixture()
        var proposal = handshake.proposal.value; proposal.version = 2
        #expect(throws: (any Error).self) { try proposal.validate(hostID: proposal.hostID, now: proposal.timestamp) }
        var changed = acceptance; changed.value = LinkAcceptance(host: acceptance.value.host, proposalDigest: "wrong", agreementKey: acceptance.value.agreementKey, epoch: acceptance.value.epoch)
        #expect(throws: (any Error).self) { try handshake.accept(changed) }
        #expect(throws: (any Error).self) { try handshake.proposal.value.validate(hostID: handshake.proposal.value.hostID, now: handshake.proposal.value.timestamp + 61) }
    }
}

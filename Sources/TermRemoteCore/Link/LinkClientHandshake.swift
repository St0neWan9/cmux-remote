import Foundation
import CryptoKit

/// Certifies a fresh key and accepts only the paired host's reply to this exact proposal.
public struct LinkClientHandshake: Sendable {
    public let proposal: SignedValue<LinkProposal>
    private let key: P256.KeyAgreement.PrivateKey
    private let host: HostIdentity
    public init(host: HostIdentity, privateKey: Data, now: Int = Int(Date().timeIntervalSince1970)) throws {
        let crypto = IdentityCryptography(); try crypto.validate(host); self.host = host
        key = P256.KeyAgreement.PrivateKey()
        proposal = try crypto.sign(LinkProposal(hostID: host.id, clientPublicKey: crypto.publicKey(privateKey: privateKey), agreementKey: key.publicKey.x963Representation, timestamp: now), domain: "link3-proposal", privateKey: privateKey)
    }
    public func accept(_ acceptance: SignedValue<LinkAcceptance>) throws -> LinkCipher {
        let crypto = IdentityCryptography(); try crypto.verify(acceptance, domain: "link3-acceptance", publicKey: host.publicKey)
        let reply = acceptance.value
        guard reply.version == 3, reply.host.id == host.id, reply.host.publicKey == host.publicKey, reply.host.certificateSHA256 == host.certificateSHA256, UUID(uuidString: reply.nonce) != nil, UUID(uuidString: reply.epoch) != nil,
              reply.proposalDigest == crypto.digest(try crypto.bytes(proposal, domain: "link3-proposal")) else { throw BridgeError("host_changed", "The link belongs to another identity or handshake.", status: 401) }
        return try LinkCipher(key: key, peerKey: reply.agreementKey, proposal: proposal, acceptance: acceptance, server: false)
    }
}

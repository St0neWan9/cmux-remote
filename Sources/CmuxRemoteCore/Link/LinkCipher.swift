import Foundation
import CryptoKit

/// RFC 9180 authenticated HPKE contexts, confined by the owning connection actor.
public struct LinkCipher: Sendable {
    private let key: P256.KeyAgreement.PrivateKey
    private let peer: P256.KeyAgreement.PublicKey
    private let receiveInfo: Data
    private var sender: HPKE.Sender
    private var recipient: HPKE.Recipient?
    private var sent = false
    public init(key: P256.KeyAgreement.PrivateKey, peerKey: Data, proposal: SignedValue<LinkProposal>, acceptance: SignedValue<LinkAcceptance>, server: Bool) throws {
        self.key = key; peer = try P256.KeyAgreement.PublicKey(x963Representation: peerKey)
        let crypto = IdentityCryptography()
        var transcript = try crypto.bytes(proposal, domain: "link3-transcript-client")
        transcript.append(try crypto.bytes(acceptance, domain: "link3-transcript-host"))
        let digest = crypto.digest(transcript)
        receiveInfo = Data(("cmux-link/3/" + digest + (server ? "/client-host" : "/host-client")).utf8)
        let sendInfo = Data(("cmux-link/3/" + digest + (server ? "/host-client" : "/client-host")).utf8)
        sender = try HPKE.Sender(recipientKey: peer, ciphersuite: .P256_SHA256_AES_GCM_256, info: sendInfo, authenticatedBy: key)
    }
    public mutating func seal(_ frame: LinkFrame) throws -> Data {
        try frame.validate()
        let bytes = try JSONEncoder().encode(frame)
        guard bytes.count <= 1_500_000 else { throw BridgeError("too_large", "Link message exceeds its bound.", status: 413) }
        let packet = SealedLinkPacket(encapsulatedKey: sent ? nil : sender.encapsulatedKey, ciphertext: try sender.seal(bytes))
        sent = true
        return try JSONEncoder().encode(packet)
    }
    public mutating func open(_ bytes: Data) throws -> LinkFrame {
        guard bytes.count <= 2_100_000 else { throw BridgeError("too_large", "Link packet exceeds its bound.", status: 413) }
        let packet = try JSONDecoder().decode(SealedLinkPacket.self, from: bytes)
        if recipient == nil {
            guard let encapsulation = packet.encapsulatedKey, encapsulation.count == 65 else { throw BridgeError("invalid_request", "Missing link encapsulation.") }
            recipient = try HPKE.Recipient(privateKey: key, ciphersuite: .P256_SHA256_AES_GCM_256, info: receiveInfo, encapsulatedKey: encapsulation, authenticatedBy: peer)
        } else if packet.encapsulatedKey != nil { throw BridgeError("invalid_request", "Link contexts cannot be reset.") }
        let plaintext = try recipient!.open(packet.ciphertext)
        guard plaintext.count <= 1_500_000 else { throw BridgeError("too_large", "Link message exceeds its bound.", status: 413) }
        let frame = try JSONDecoder().decode(LinkFrame.self, from: plaintext); try frame.validate(); return frame
    }
}

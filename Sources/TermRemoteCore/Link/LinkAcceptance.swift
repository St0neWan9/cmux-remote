import Foundation

/// Host certification binds the complete proposal, epoch and fresh agreement key.
public struct LinkAcceptance: Codable, Sendable {
    public let version: Int
    public let host: HostIdentity
    public let proposalDigest: String
    public let agreementKey: Data
    public let nonce: String
    public let epoch: String
    public init(host: HostIdentity, proposalDigest: String, agreementKey: Data, epoch: String, nonce: String = UUID().uuidString) {
        version = 3; self.host = host; self.proposalDigest = proposalDigest; self.agreementKey = agreementKey; self.nonce = nonce; self.epoch = epoch
    }
}

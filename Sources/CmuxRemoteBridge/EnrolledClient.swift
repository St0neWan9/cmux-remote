import Foundation
import CmuxRemoteCore

/// Host-owned authorization record. Public keys are not shared bearer credentials.
public struct EnrolledClient: Codable, Sendable {
    public var id: String
    public var publicKey: String
    public var name: String
    public var kind: String
    public var scope: ClientScope
    public var revoked: Bool
    public var grant: SignedValue<EnrollmentGrant>
}

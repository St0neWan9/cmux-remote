import CmuxRemoteCore

/// The phone coordinates enrollment through this seam without owning transport details.
public protocol DeviceEnrolling: AnyObject, Sendable {
    var request: SignedValue<EnrollmentRequest> { get }
    func submit() async throws -> EnrollmentStatus
    func status() async throws -> EnrollmentStatus
    func cancel() async throws
    func close()
    func connection(from status: EnrollmentStatus) throws -> AuthorizedConnection
}

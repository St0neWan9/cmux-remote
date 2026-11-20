import Foundation
import TermRemoteCore

/// A conversation together with the Mac that owns it; IDs only need to be unique within one Mac.
struct HostedSession: Identifiable {
    let hostID: String
    let hostName: String
    let session: SessionDescriptor
    var id: String { hostID + ":" + session.id }
}

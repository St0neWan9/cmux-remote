import Foundation
import CmuxRemoteCore
import CmuxRemoteClient

/// One approved Mac and its own client; every request to that Mac uses this client and grant.
struct HostLink: Identifiable {
    let id: String
    var name: String
    let client: RemoteClient
    var connection: AuthorizedConnection?
    var endpoint: String? { connection.map { $0.endpoint.host + ":" + String($0.endpoint.port) } }
}

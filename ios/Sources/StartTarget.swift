import Foundation
import CmuxRemoteCore
import CmuxRemoteClient

/// A workspace this device may start sessions in, with the Mac that owns it.
struct StartTarget: Identifiable {
    let hostID: String
    let hostName: String
    let workspace: WorkspaceSummary
    let client: RemoteClient
    var id: String { hostID + "/" + workspace.id.lowercased() }
}

import Foundation
import Observation
import CmuxExtensionKit
import CmuxRemoteClient
import CmuxRemoteMac

/// Sidebar-only state; credentials, process creation and mirroring remain in the Companion.
@MainActor @Observable final class RemoteSidebarModel {
    private(set) var context: CmuxSidebarContext?
    private(set) var errorCode: String?
    func update(_ context: CmuxSidebarContext) { self.context = context }
    func selectWorkspace(_ id: UUID) async {
        do { try await context?.host.selectWorkspace(id); errorCode = nil }
        catch { errorCode = "sidebar_permission" }
    }
}

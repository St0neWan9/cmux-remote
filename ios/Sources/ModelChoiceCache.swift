import Foundation
import CmuxRemoteCore

/// The model choices each Mac offers per agent, shared by every conversation on this phone.
///
/// The choices come from the agent's own configuration on the Mac, not from one conversation, so one read
/// serves every Claude (or Codex) conversation on that Mac. A conversation opened briefly no longer has to wait
/// out its own read before its header offers the menu; it shows the Mac's last list and refreshes it.
@MainActor
final class ModelChoiceCache {
    private var lists: [String: ModelChoiceList] = [:]
    init() {}
    /// `scope` names the Mac and this phone's grant on it, so two Macs never share a list.
    func list(scope: String, agent: String) -> ModelChoiceList? { lists[scope + ":" + agent] }
    func store(_ list: ModelChoiceList, scope: String, agent: String) { lists[scope + ":" + agent] = list }
}

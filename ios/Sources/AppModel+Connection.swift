import Foundation
import CmuxRemoteClient

/// Keeps every approved Mac's link up and makes its state visible.
extension AppModel {
    /// The state the pages show: dialing wins over a failure so a retry is visible as soon as it starts.
    /// A Mac retried in the background is left out, so its dial does not keep turning the bar.
    var connectionState: LinkState? {
        let states = links.filter { !quietHosts.contains($0.id) }.compactMap { linkStates[$0.id] }
        if states.contains(.connecting) { return .connecting }
        if states.contains(.disconnected) { return .disconnected }
        return states.isEmpty ? nil : .connected
    }

    /// Dials Macs again and reloads the lists.
    ///
    /// Returning from a long background redials every Mac, since its links are likely half-open. Automatic retries,
    /// the bar's Retry and a pull touch only Macs already known to be down: redialing a working link drops its live updates.
    /// A person's retry starts the backoff over and shows the Macs retried in the background again.
    func reconnect(onlyLost: Bool = false) async {
        reconnectSchedule.rearm(); quietHosts.removeAll()
        await redial(onlyLost ? links.filter { linkStates[$0.id] != .connected } : links)
    }

    /// A person's retry on one Mac's page: that Mac is dialed again and shown dialing, even if it was retried quietly.
    func reconnect(client: RemoteClient) async {
        guard let link = links.first(where: { $0.client === client }) else { await client.reconnect(); return }
        reconnectSchedule.rearm(); quietHosts.remove(link.id)
        // A link already up reports its own drop and dial; one kept for a write in flight reports nothing and must
        // not be left showing a dial that never happens.
        if linkStates[link.id] != .connected { linkStates[link.id] = .connecting }
        await client.reconnect()
        await refresh()
    }

    private func redial(_ targets: [HostLink]) async {
        guard !targets.isEmpty else { return }
        // The bar turns at once, before a slow relay dial has reported anything.
        for link in targets where linkStates[link.id] != .connected { linkStates[link.id] = .connecting }
        await withTaskGroup(of: Void.self) { group in
            for link in targets { let client = link.client; group.addTask { await client.reconnect() } }
        }
        await refresh()
    }

    /// A pull reloads the lists over working links and redials only the Macs that are down.
    func pullToRefresh() async {
        if links.contains(where: { linkStates[$0.id] != .connected }) { await reconnect(onlyLost: true) } else { await refresh() }
    }

    /// Runs while the app is in the foreground: follows each link, redials when the network returns, and retries a lost Mac.
    func superviseConnections(network: NetworkPathMonitor = NetworkPathMonitor()) async {
        let observed = links.map { ($0.id, $0.client) }
        let schedule = reconnectSchedule
        // Each link is followed from the first moment, before a return from the background checks or redials it.
        // Following only began after that redial, so the list kept the state it had before the app left — connected —
        // while the link was down and dialing; a conversation opened meanwhile reads its link directly and said it was
        // reconnecting, although the list had just said the Mac was connected.
        await withTaskGroup(of: Void.self) { group in
            for (id, client) in observed {
                group.addTask { [weak self] in
                    // The client's own previous report, not `linkStates`: a failed list read may mark it down first.
                    var previous: LinkState?
                    for await state in client.linkStates() {
                        guard let self else { return }
                        diagLog(state == .disconnected ? .warning : .info, category: "link",
                                "state=\(state) host=\(id.prefix(8))")
                        await MainActor.run {
                            self.linkStates[id] = state
                            if state == .connected { self.quietHosts.remove(id) }
                            schedule.observe(host: id, from: previous, to: state)
                        }
                        previous = state
                    }
                }
            }
            group.addTask { [weak self] in
                // A new or changed path (Wi-Fi to cellular included) leaves sockets bound to the old one.
                for await usable in network.availability() where usable {
                    guard let self else { return }
                    diagLog(.info, category: "link", "redial all: network path changed")
                    await self.reconnect()
                }
            }
            group.addTask { [weak self] in
                // The return's own check or redial goes first, so the automatic retries never overlap it: a drop it
                // causes is seen by the schedule, and by the time the first retry looks the link is back.
                await self?.relinkAfterBackground()
                // A working link that drops is dialed again at once; a Mac that stays unreachable is tried again
                // with growing pauses, so the bar never sits still. Automatic retries start only here, so they never overlap.
                while !Task.isCancelled {
                    let full = await schedule.wait()
                    guard !Task.isCancelled, let self else { return }
                    await self.retry(schedule, waited: full)
                }
            }
            await group.waitForAll()
        }
    }

    /// Brings the links back after the app was away: a kept link is checked, a lost one is dialed again.
    private func relinkAfterBackground() async {
        guard let backgroundedAt else { return }
        let away = Int(Date().timeIntervalSince(backgroundedAt))
        self.backgroundedAt = nil
        if linksKeptInBackground() {
            // The app kept running through a short absence, so its links may still be up: each is checked with a
            // ping of a few seconds and only the ones that fail are dialed again. Redialing every return made the
            // page say it was reconnecting after any glance at another app.
            var checks: [String: Bool] = [:]
            await withTaskGroup(of: (String, Bool).self) { group in
                for link in links { let client = link.client, id = link.id; group.addTask { (id, await client.verifyLink()) } }
                for await (id, alive) in group { checks[id] = alive }
            }
            let lost = links.filter { checks[$0.id] != true }
            diagLog(.info, category: "link", "returned after \(away)s with links kept; redial \(lost.count) of \(links.count)")
            if lost.isEmpty { await refresh() } else { reconnectSchedule.rearm(); await redial(lost) }
        } else {
            // A suspended app's sockets are torn down within a couple of seconds, so after a longer absence a link
            // from before is gone. Redialing at once costs about two seconds; the alternative is a link that still
            // looks connected and a request that waits out its twenty second deadline before the phone admits it.
            diagLog(.info, category: "link", "redial all: returned after \(away)s in background")
            await reconnect()
        }
    }

    /// One Mac's link as every page shows it: the list's tab and the conversation's bar read this, so they agree.
    ///
    /// A Mac retried in the background reads as unreachable rather than dialing, as on its tab. The conversation page
    /// used to read its link directly, so it could say "reconnecting" for a Mac the list showed as connected or as
    /// quietly retried.
    func shownLinkState(of client: RemoteClient) -> LinkState? {
        guard let link = links.first(where: { $0.client === client }), let state = linkStates[link.id] else { return nil }
        if state == .connecting, quietHosts.contains(link.id) { return .disconnected }
        return state
    }

    private func retry(_ schedule: ReconnectSchedule, waited full: Bool) async {
        var states: [String: LinkState] = [:]
        for link in links { if let state = linkStates[link.id] { states[link.id] = state } }
        switch schedule.step(states: states, waited: full) {
        case .idle:
            return
        case .redialDropped(let hosts):
            // A link that just worked and dropped is news: show its redial again.
            quietHosts.subtract(hosts)
            diagLog(.info, category: "link", "auto retry #1 at once: link dropped host=\(hosts.map { String($0.prefix(8)) }.joined(separator: ","))")
            await redial(links.filter { hosts.contains($0.id) })
        case .retryLost(let attempt, let waited):
            let lost = links.filter { linkStates[$0.id] != .connected }.map(\.id)
            if schedule.quiet, !lost.allSatisfy(quietHosts.contains) {
                quietHosts.formUnion(lost)
                diagLog(.info, category: "link", "auto retry continues in the background; next every \(schedule.pause.components.seconds)s at most 256s")
            }
            diagLog(.info, category: "link", "auto retry #\(attempt) after waiting \(waited.components.seconds)s")
            // The automatic path must not rearm the budget it just spent.
            await redial(links.filter { linkStates[$0.id] != .connected })
        }
    }
}

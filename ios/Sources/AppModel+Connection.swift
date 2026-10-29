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
    /// The state of one Mac's link, for a conversation that belongs to it.
    func connectionState(of client: RemoteClient) -> LinkState? {
        links.first { $0.client === client }.flatMap { linkStates[$0.id] }
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
        if let backgroundedAt {
            // iOS tears the socket down within a couple of seconds of the app leaving the foreground (the bridge
            // log shows the channel closing two seconds after the page's subscriptions are cancelled), so a link
            // from before is gone however short the absence was. Redialing on return costs about two seconds; the
            // alternative is a link that still looks connected and a request that waits out its twenty second
            // deadline before the phone admits it is not.
            diagLog(.info, category: "link", "redial all: returned after \(Int(Date().timeIntervalSince(backgroundedAt)))s in background")
            self.backgroundedAt = nil
            await reconnect()
        }
        let observed = links.map { ($0.id, $0.client) }
        let schedule = reconnectSchedule
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

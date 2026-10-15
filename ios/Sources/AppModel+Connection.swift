import Foundation
import CmuxRemoteClient

/// Keeps every approved Mac's link up and makes its state visible.
extension AppModel {
    /// The state the pages show: dialing wins over a failure so a retry is visible as soon as it starts.
    var connectionState: LinkState? {
        let states = links.compactMap { linkStates[$0.id] }
        if states.contains(.connecting) { return .connecting }
        if states.contains(.disconnected) { return .disconnected }
        return states.isEmpty ? nil : .connected
    }
    /// The Mac to name in the bar when exactly one of several is unreachable.
    var offlineHostName: String? {
        let offline = links.filter { linkStates[$0.id] == .disconnected }
        return links.count > 1 && offline.count == 1 ? offline.first?.name : nil
    }
    /// The state of one Mac's link, for a conversation that belongs to it.
    func connectionState(of client: RemoteClient) -> LinkState? {
        links.first { $0.client === client }.flatMap { linkStates[$0.id] }
    }

    /// Dials Macs again and reloads the lists.
    ///
    /// Returning from a long background redials every Mac, since its links are likely half-open. Automatic retries,
    /// the bar's Retry and a pull touch only Macs already known to be down: redialing a working link drops its live updates.
    func reconnect(onlyLost: Bool = false) async {
        let targets = onlyLost ? links.filter { linkStates[$0.id] != .connected } : links
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
        if let backgroundedAt, Date().timeIntervalSince(backgroundedAt) > 20 {
            // iOS suspends sockets in the background; a link from before is unlikely to still be alive.
            diagLog(.info, category: "link", "redial all: returned after \(Int(Date().timeIntervalSince(backgroundedAt)))s in background")
            self.backgroundedAt = nil
            await reconnect()
        }
        let observed = links.map { ($0.id, $0.client) }
        await withTaskGroup(of: Void.self) { group in
            for (id, client) in observed {
                group.addTask { [weak self] in
                    for await state in client.linkStates() {
                        guard let self else { return }
                        diagLog(state == .disconnected ? .warning : .info, category: "link",
                                "state=\(state) host=\(id.prefix(8))")
                        await MainActor.run { self.linkStates[id] = state }
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
                // A Mac that stays unreachable is tried again with growing pauses, so the bar never sits still.
                var attempt = 0
                while !Task.isCancelled {
                    let pause = [3, 5, 10, 20, 30][min(attempt, 4)]
                    do { try await Task.sleep(for: .seconds(pause)) } catch { return }
                    guard let self else { return }
                    if await self.connectionState == .disconnected {
                        attempt += 1
                        diagLog(.info, category: "link", "auto retry #\(attempt) after waiting \(pause)s")
                        await self.reconnect(onlyLost: true)
                    } else { attempt = 0 }
                }
            }
            await group.waitForAll()
        }
    }
}

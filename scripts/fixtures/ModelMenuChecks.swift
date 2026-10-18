import Foundation
import CmuxRemoteCore
import CmuxRemoteClient

/// The model menu belongs to the Mac and the agent: one conversation's read serves every other one.
enum ModelMenuChecks {
    @MainActor static func run() async -> (count: Int, failures: [String]) {
        var count = 0, failures: [String] = []
        func check(_ condition: Bool, _ message: String) { count += 1; if !condition { failures.append(message) } }
        // Two Macs differ by their certificate, which is what names a Mac's scope on this phone.
        func client(_ port: Int, _ certificate: Character) -> RemoteClient {
            RemoteClient(pairing: try! PairingConfiguration(host: "localhost", port: port, token: String(repeating: "0", count: 32), certificateSHA256: String(repeating: certificate, count: 64)))
        }
        let studio = client(1, "a"), laptop = client(2, "b")
        defer { studio.close(); laptop.close() }
        let claude = ModelChoiceList(choices: [ModelChoice(id: "opus", label: "Opus"), ModelChoice(id: "haiku", label: "Haiku")], acceptsCustom: true, persistsDefault: true)
        func session(_ id: String, agent: String = "claude") -> SessionDescriptor {
            SessionDescriptor(id: id, agent: agent, title: id, cwd: nil, workspaceID: "workspace", surfaceID: "surface-" + id, state: "idle")
        }
        let cache = ModelChoiceCache()
        let reads = Counter()
        func model(_ id: String, on client: RemoteClient, agent: String = "claude", read: @escaping @Sendable () async throws -> ModelChoiceList) -> ConversationModel {
            ConversationModel(session: session(id, agent: agent), client: client, readModels: { await reads.add(); return try await read() }, modelCache: cache)
        }

        // The first conversation reads the Mac's list.
        let first = model("first", on: studio) { claude }
        await first.loadModelChoices()
        check(first.canSwitchModel && first.modelChoices == claude, "A conversation that read its models offered no menu")

        // A second conversation whose own read is slow or fails still offers the Mac's list at once.
        let slow = model("second", on: studio) { throw URLError(.timedOut) }
        await slow.loadModelChoices()
        check(slow.canSwitchModel && slow.modelChoices == claude, "Another conversation on the same Mac waited for its own read before offering a menu")

        // The list is per agent and per Mac: Codex, or another Mac, never shows Claude's choices on this one.
        let codex = model("codex", on: studio, agent: "codex") { throw URLError(.timedOut) }
        await codex.loadModelChoices()
        check(codex.modelChoices == nil, "A Codex conversation showed Claude's model list")
        let other = model("other", on: laptop) { throw URLError(.timedOut) }
        await other.loadModelChoices()
        check(other.modelChoices == nil, "Another Mac's conversation showed this Mac's model list")

        // A read that failed is made again the next time the page opens.
        let flaky = ReadSwitch(); await flaky.set(true)
        let retried = model("retried", on: laptop) { if await flaky.on { throw URLError(.networkConnectionLost) }; return claude }
        await retried.loadModelChoices()
        check(retried.modelChoices == nil, "A failed read produced a menu")
        await flaky.set(false)
        await retried.loadModelChoices()
        check(retried.canSwitchModel, "Reopening after a failed read did not read the models again")

        // Every visit reads again: the owner edits the agent's configuration while the app keeps running.
        let edited = ModelChoiceList(choices: [ModelChoice(id: "sonnet", label: "Sonnet")], acceptsCustom: true, persistsDefault: true)
        let mac = ListSource(claude)
        let visited = model("visited", on: studio) { await mac.list }
        await visited.loadModelChoices()
        check(visited.modelChoices == claude, "The first visit did not show the Mac's list")
        await mac.set(edited)
        await visited.loadModelChoices()
        check(visited.modelChoices == edited, "A conversation opened again kept the list it read before the Mac's configuration changed")
        // The new list is what every other conversation on that Mac shows first.
        let next = model("next", on: studio) { throw URLError(.timedOut) }
        await next.loadModelChoices()
        check(next.modelChoices == edited, "Another conversation showed the Mac's old list after one had read the new one")
        // A refresh that fails keeps the list already shown rather than taking the menu away.
        let failing = model("visited", on: studio) { throw URLError(.timedOut) }
        await failing.loadModelChoices()
        check(failing.modelChoices == edited, "A failed refresh took the menu away")

        // A conversation that cannot send cannot switch, and reads nothing.
        let ended = ConversationModel(session: SessionDescriptor(id: "ended", agent: "claude", title: "ended", cwd: nil, workspaceID: "workspace", surfaceID: "surface", state: "ended"),
                                      client: studio, readModels: { await reads.add(); return claude }, modelCache: cache)
        let readsBefore = await reads.value
        await ended.loadModelChoices()
        let readsAfter = await reads.value
        check(!ended.canSwitchModel && readsAfter == readsBefore, "An ended conversation offered or read a model menu")
        return (count, failures)
    }
}

private actor Counter { var value = 0; func add() { value += 1 } }
private actor ReadSwitch { var on = false; func set(_ value: Bool) { on = value } }
private actor ListSource { var list: ModelChoiceList; init(_ list: ModelChoiceList) { self.list = list }; func set(_ value: ModelChoiceList) { list = value } }

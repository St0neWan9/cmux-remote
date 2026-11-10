import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteClient

@Suite struct LinkCapacityTests {
    /// A return to the app sends every page's reads at once. Past the link's eight, a read waits for a slot; it used to
    /// fail as busy, and the page dropped it as a connection hiccup and kept showing what it had before the switch.
    @Test(.timeLimit(.minutes(1))) func readsBeyondTheLinksSlotsWaitInsteadOfFailing() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let client = try RemoteClient(connection: fixture.connection)
        defer { client.close() }
        // A fresh link has no epoch yet, so every one of these also needs the identity read first.
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<(LinkClientConnection.slotLimit * 3) {
                group.addTask { (try? await client.get("/v1/sessions", as: [SessionDescriptor].self)) != nil }
            }
            return await group.reduce(into: [Bool]()) { $0.append($1) }
        }
        #expect(results.count == LinkClientConnection.slotLimit * 3)
        #expect(results.allSatisfy { $0 }, "\(results.filter { !$0 }.count) reads failed")
        await fixture.stop()
    }
    /// A link kept while the app was away is checked before it is trusted: one that answers is kept, and one whose
    /// Mac went away is reported at once, so the return dials again instead of a read waiting out its deadline.
    @Test(.timeLimit(.minutes(1))) func aKeptLinkIsCheckedBeforeItIsTrusted() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        let client = try RemoteClient(connection: fixture.connection)
        defer { client.close() }
        #expect(await client.verifyLink() == false, "A link never dialed was reported alive")
        _ = try await client.get("/v1/sessions", as: [SessionDescriptor].self)
        #expect(await client.verifyLink())
        await fixture.stop()
        let started = ContinuousClock.now
        #expect(await client.verifyLink() == false)
        #expect(ContinuousClock.now - started < .seconds(5))
    }
}

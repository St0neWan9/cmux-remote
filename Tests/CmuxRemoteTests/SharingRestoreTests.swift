import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

/// The resident restores the owner's last explicit sharing choice after a restart, and only that.
@Suite struct SharingRestoreTests {
    private func service(_ fixture: LinkIntegrationFixture, remembers: Bool) -> ManagedSharingService {
        let sessions = SessionService(cmux: fixture.cmux, home: fixture.root.appendingPathComponent("home"), transcriptRoots: [fixture.root])
        return ManagedSharingService(state: BridgeState(directory: fixture.root), authority: fixture.authority,
            router: BridgeRouter(service: sessions, authority: fixture.authority), port: 0, advertise: false, remembersChoice: remembers)
    }
    @Test func explicitChoiceIsRestoredAndAnExplicitStopIsRespected() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        do {
            let repository = SharingPreferenceRepository(directory: fixture.root)
            let first = service(fixture, remembers: true)
            let started = try await first.start()
            let port = try #require(started["port"].int)
            #expect(repository.load() == .init(enabled: true, port: port))
            // The resident restarts: the next instance finds the remembered choice. Free the port first.
            _ = await first.stop(); try repository.save(.init(enabled: true, port: port))
            let restarted = service(fixture, remembers: true)
            await restarted.restore()
            #expect(await restarted.status()["state"].string == "running")
            #expect(await restarted.status()["port"].int == port)
            _ = await restarted.stop()
            #expect(repository.load()?.enabled == false)
            let afterStop = service(fixture, remembers: true)
            await afterStop.restore()
            #expect(await afterStop.status()["state"].string == "stopped")
            await fixture.stop()
        } catch { await fixture.stop(); throw error }
    }
    @Test func serveModeAndUntrustedFilesNeverStartSharing() async throws {
        let fixture = try await LinkIntegrationFixture.create()
        do {
            let repository = SharingPreferenceRepository(directory: fixture.root)
            let serve = service(fixture, remembers: false)
            _ = try await serve.start(); _ = await serve.stop()
            #expect(repository.load() == nil, "A CLI serve run must not record a resident preference")
            let file = fixture.root.appendingPathComponent("sharing.json")
            try Data(#"{"enabled":true,"port":7740}"#.utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
            #expect(repository.load() == nil, "A file others can write must not start sharing")
            try Data("not json".utf8).write(to: file)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            let resident = service(fixture, remembers: true)
            await resident.restore()
            #expect(await resident.status()["state"].string == "stopped")
            await fixture.stop()
        } catch { await fixture.stop(); throw error }
    }
}

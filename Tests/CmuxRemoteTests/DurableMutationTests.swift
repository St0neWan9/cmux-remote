import Foundation
import Testing
import CmuxRemoteCore
import CmuxRemoteBridge

@Suite struct DurableMutationTests {
    func service(_ fixture: DurableMutationFixture, directory: URL, capacity: Int = 16_384) -> SessionService {
        .init(cmux: fixture, home: directory, transcriptRoots: [], mutations: MutationLedger(directory: directory, capacity: capacity))
    }
    func mutate(_ service: SessionService, action: String, id: UUID, client: String = "device-a") async throws -> MutationReceipt {
        let access = SessionAccess(clientID: client) { _, workspace in #expect(workspace == "workspace") }
        switch action {
        case "send": return try await service.send(id: "session", request: .init(text: "private-prompt-never-persist", operationID: id), access: access)
        case "interrupt": return try await service.interrupt(id: "session", request: .init(operationID: id), access: access)
        default: return try await service.reply(requestID: "request", body: .object(["operation_id": .string(id.uuidString), "kind": .string("permissionRequest"), "mode": .string("once")]), access: access)
        }
    }
    @Test(arguments: ["send", "interrupt", "reply"])
    func completedAndUnknownMutationsRemainDeduplicatedAfterRestart(action: String) async throws {
        for fail in [false, true] {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let fixture = DurableMutationFixture(), id = UUID()
            await fixture.configure(directory: directory)
            if fail { await fixture.failWrites() }
            let first = service(fixture, directory: directory)
            if fail { await #expect(throws: BridgeError.self) { _ = try await mutate(first, action: action, id: id) } }
            else { #expect(try await mutate(first, action: action, id: id).accepted) }
            let restarted = service(fixture, directory: directory)
            if fail { await #expect(throws: BridgeError.self) { _ = try await mutate(restarted, action: action, id: id) } }
            else { #expect(try await mutate(restarted, action: action, id: id).accepted) }
            #expect(await fixture.writes.count == 1)
            let path = directory.appendingPathComponent("mutation-receipts.ndjson")
            let raw = try String(contentsOf: path, encoding: .utf8)
            #expect(!raw.contains("private-prompt-never-persist"))
            let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
            #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        }
    }
    @Test func deviceIDsSeparateReceiptsAndReplayStillRequiresCurrentScope() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = DurableMutationFixture(), id = UUID(), owner = service(fixture, directory: directory)
        _ = try await mutate(owner, action: "send", id: id)
        _ = try await mutate(owner, action: "send", id: id, client: "device-b")
        #expect(await fixture.writes.count == 2)
        let restarted = service(fixture, directory: directory)
        await #expect(throws: BridgeError.self) {
            _ = try await restarted.send(id: "session", request: .init(text: "private-prompt-never-persist", operationID: id),
                access: SessionAccess(clientID: "device-a") { _, _ in throw BridgeError("scope_denied", "Revoked", status: 403) })
        }
        #expect(await fixture.writes.count == 2)
    }
    @Test func corruptionOrFullStorageStopsWritesWithoutEvictingOldIntents() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = DurableMutationFixture(), id = UUID(), owner = service(fixture, directory: directory, capacity: 1)
        _ = try await mutate(owner, action: "send", id: id)
        await #expect(throws: BridgeError.self) { _ = try await mutate(owner, action: "send", id: UUID()) }
        #expect(await fixture.writes.count == 1)
        _ = try await mutate(service(fixture, directory: directory, capacity: 1), action: "send", id: id)
        try Data("corrupt".utf8).write(to: directory.appendingPathComponent("mutation-receipts.ndjson"))
        await #expect(throws: (any Error).self) { _ = try await mutate(service(fixture, directory: directory), action: "send", id: UUID()) }
        #expect(await fixture.writes.count == 1)
    }
    @Test func completionPersistenceFailureKeepsIntentUnknownAfterRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = DurableMutationFixture(), id = UUID()
        await fixture.configure(directory: directory, loseCompletion: true)
        await #expect(throws: BridgeError.self) { _ = try await mutate(service(fixture, directory: directory), action: "send", id: id) }
        let file = directory.appendingPathComponent("mutation-receipts.ndjson")
        try FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: directory.appendingPathComponent("reserved-backup.json"), to: file)
        await #expect(throws: BridgeError.self) { _ = try await mutate(service(fixture, directory: directory), action: "send", id: id) }
        #expect(await fixture.writes.count == 1)
    }
    @Test func unavailableJournalStoragePreventsBackendExecution() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let obstruction = directory.appendingPathComponent("not-a-directory")
        try Data("fixture".utf8).write(to: obstruction)
        let fixture = DurableMutationFixture()
        do { _ = try await mutate(service(fixture, directory: obstruction), action: "send", id: UUID()); Issue.record("Expected storage rejection") }
        catch { #expect((error as? BridgeError)?.code == "receipt_storage") }
        #expect(await fixture.writes.isEmpty)
    }

    @Test func unconfirmedSubmissionCannotBecomeASuccessReceiptOrExecuteAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixture = DurableMutationFixture(), id = UUID()
        await fixture.rejectSubmission()
        for _ in 0..<2 {
            do { _ = try await mutate(service(fixture, directory: directory), action: "send", id: id); Issue.record("Expected unconfirmed submission") }
            catch { #expect((error as? BridgeError)?.code == "outcome_unknown") }
        }
        #expect(await fixture.writes.count == 1)
    }

}

import Foundation
import Testing
import CmuxRemoteCore
@testable import CmuxRemoteBridge

private actor MigrationBackend: CmuxControlling {
    var calls = 0
    func request(_ method: String, params: [String: JSONValue]) async throws -> JSONValue { calls += 1; return .object([:]) }
}
@Suite struct IntegratedMutationMigrationTests {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("cmux-integrated-receipts-" + UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700]); return root
    }
    @Test func priorPhoneReceiptsAndUnknownIntentsSurviveSharedLedgerMigrationWithoutDispatch() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at:root) }
        let request = SendRequest(text:"Private legacy caption")
        let interrupted = InterruptRequest()
        var legacy = try MutationJournal(file:root.appendingPathComponent("operations.json"))
        try legacy.begin(id:request.operationID,signature:"send:session:\(request.text)",principal:"deviceA",resource:"session:session",workspace:"workspace",capability:.conversationControl)
        _ = try legacy.complete(id:request.operationID)
        try legacy.begin(id:interrupted.operationID,signature:"interrupt:session:false",principal:"deviceA",resource:"session:session",workspace:"workspace",capability:.conversationControl)
        let backend = MigrationBackend(); let access = SessionAccess(clientID:"deviceA") { _, workspace in #expect(workspace == "workspace") }
        let store = MutationLedger(directory:root)
        let service = SessionService(cmux:backend,home:root,transcriptRoots:[],mutations:store)
        #expect(try await service.send(id:"session",request:request,access:access).accepted)
        #expect(try await service.operationStatus(id:request.operationID,access:access).state == .accepted)
        #expect(try await service.operationStatus(id:interrupted.operationID,access:access).state == .outcomeUnknown)
        do { _ = try await service.interrupt(id:"session",request:interrupted,access:access); Issue.record("Migration repeated an unresolved interrupt") }
        catch { #expect((error as? BridgeError)?.code == "outcome_unknown") }
        do { _ = try await service.send(id:"session",request:SendRequest(text:"Changed caption",operationID:request.operationID),access:access); Issue.record("Migration lost input fingerprint") }
        catch { #expect((error as? BridgeError)?.code == "operation_conflict") }
        let restarted = SessionService(cmux:backend,home:root,transcriptRoots:[],mutations:MutationLedger(directory:root))
        #expect(try await restarted.send(id:"session",request:request,access:access).accepted)
        let journal = try String(contentsOf:root.appendingPathComponent("mutation-receipts.ndjson"),encoding:.utf8)
        #expect(journal.split(separator:"\n").count == 2 && !journal.contains(request.text))
        #expect(await backend.calls == 0)
        let other = SessionAccess(clientID:"deviceB") { _, _ in }
        do { _ = try await restarted.operationStatus(id:request.operationID,access:other); Issue.record("Migration exposed another device's receipt") }
        catch { #expect((error as? BridgeError)?.code == "scope_denied") }
    }
    @Test func corruptedPriorPhoneStoreBlocksNewLedgerWrites() async throws {
        let root = try directory(); defer { try? FileManager.default.removeItem(at:root) }
        try Data("corrupt".utf8).write(to:root.appendingPathComponent("operations.json"))
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:root.appendingPathComponent("operations.json").path)
        let store = MutationLedger(directory:root)
        do { _ = try await store.begin(clientID:"device",operationID:UUID(),fingerprint:String(repeating:"a",count:64),workspaceID:"workspace",capability:.terminalInput); Issue.record("Corrupt legacy state was ignored") }
        catch { #expect((error as? BridgeError)?.code == "journal_unavailable") }
        #expect(!FileManager.default.fileExists(atPath:root.appendingPathComponent("mutation-receipts.ndjson").path))
    }
}

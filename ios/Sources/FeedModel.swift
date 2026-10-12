import Foundation
import Observation
import CmuxRemoteCore
import CmuxRemoteClient

/// Snapshot refresh and replies share one model, preserving mutation warnings across background reads.
@MainActor @Observable
final class FeedModel {
    var items: [JSONValue] = []
    var loading = false
    var busy = false
    var showHistory = false
    private var readError: String?
    private var writeError: String?
    var error: String? { writeError ?? readError }
    private let reads = ReadRequestOwner()
    private var readsEnabled = true
    private let fetch: @Sendable () async throws -> [JSONValue]
    private let send: @Sendable (String, JSONValue) async throws -> MutationReceipt
    init(fetch: @escaping @Sendable () async throws -> [JSONValue], send: @escaping @Sendable (String, JSONValue) async throws -> MutationReceipt) { self.fetch = fetch; self.send = send }
    convenience init(client: RemoteClient) {
        self.init(fetch: { try await client.get("/v1/feed", as: JSONValue.self)["items"].array ?? [] }, send: { id, body in
            try await client.post("/v1/feed/\(id)/reply", body: body, as: MutationReceipt.self)
        })
    }
    func suspendReads() { readsEnabled = false; reads.suspend(); loading = false }
    func resumeReads() { readsEnabled = true }
    func refresh() async {
        guard readsEnabled else { return }
        await reads.run { [self] request in
            loading = true
            defer { if reads.revision == request { loading = false } }
            do { let snapshot = try await fetch(); guard reads.isCurrent(request) else { return }; items = snapshot; readError = nil }
            catch { if reads.isCurrent(request) { readError = ErrorPresentation().message(error) } }
        }
    }
    func reply(_ item: JSONValue, mode: FeedDecisionMode? = nil, feedback: String? = nil, selections: [String]? = nil) async {
        guard let id = item["request_id"].string, item["status"].string == "pending", !busy else { return }
        busy = true; writeError = nil; defer { busy = false }
        var fields: [String: JSONValue] = ["operation_id": .string(UUID().uuidString), "kind": item["kind"]]
        if let mode { fields["mode"] = .string(mode.rawValue) }
        if let feedback, !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { fields["feedback"] = .string(feedback) }
        if let selections { fields["selections"] = .array(selections.map(JSONValue.string)) }
        do { _ = try await send(id, .object(fields)); await refresh() }
        catch { if !Task.isCancelled { writeError = ErrorPresentation().message(error) } }
    }
}

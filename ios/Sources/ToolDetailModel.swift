import Foundation
import Observation
import CmuxRemoteCore
import CmuxRemoteClient

/// Owns one bounded detail page; content revisions prevent mixed tool output.
@MainActor @Observable
final class ToolDetailModel {
    let reference: ToolDetailReference
    var field: String
    private(set) var page: ToolTextPage?
    private(set) var busy = false
    private(set) var error: String?
    private var requestID = UUID()
    private var generation: String
    private var requiresReanchor = false
    private let fetch: @Sendable ([String: String]) async throws -> ToolTextPage
    init(reference: ToolDetailReference, fetch: @escaping @Sendable ([String: String]) async throws -> ToolTextPage) {
        self.reference = reference; field = reference.initialField; self.fetch = fetch; generation = reference.generation
    }
    func suspend() { requestID = UUID(); busy = false }
    func load(offset: Int = 0, preserveRevision: Bool = false) async {
        let request = UUID(); requestID = request; busy = true
        let chosen = field
        if page?.field != chosen { page = nil }
        let readCurrent = requiresReanchor && offset == 0 && !preserveRevision
        let chosenGeneration = readCurrent ? "current" : generation
        defer { if requestID == request { busy = false } }
        var query = ["message_id": reference.messageID, "generation": chosenGeneration,
                     "field": chosen, "offset": String(offset), "limit": "16384"]
        if preserveRevision, let page { query["content_id"] = page.contentID }
        do {
            let result = try await fetch(query)
            guard !Task.isCancelled, requestID == request else { return }
            guard result.messageID == reference.messageID, (readCurrent ? !result.generation.isEmpty && result.generation != "current" && result.generation.utf8.count <= 128 : result.generation == chosenGeneration),
                  result.field == chosen, result.offset == offset, result.totalCharacters >= offset,
                  result.totalCharacters <= 33_554_432, result.text.unicodeScalars.count <= 16_384, result.text.utf8.count <= 65_536,
                  result.contentID.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                  offset + result.text.unicodeScalars.count <= result.totalCharacters,
                  result.nextOffset == (offset + result.text.unicodeScalars.count < result.totalCharacters ? offset + result.text.unicodeScalars.count : nil),
                  query["content_id"] == nil || query["content_id"] == result.contentID else { throw BridgeError("invalid_response", "The tool detail page could not be verified.", status: 502) }
            generation = result.generation; requiresReanchor = false; page = result; error = nil
        } catch {
            guard !Task.isCancelled, requestID == request else { return }
            if let failure = error as? BridgeError, failure.code == "stale_detail" { requiresReanchor = true; self.error = String(localized: "tool.detail.changed") }
            else if let failure = error as? BridgeError, failure.code == "not_found" { self.error = String(localized: "tool.detail.unavailable") }
            else { self.error = ErrorPresentation().message(error) }
        }
    }
}

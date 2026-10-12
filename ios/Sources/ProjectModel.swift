import Foundation
import Observation
import CmuxRemoteCore
import CmuxRemoteClient

@MainActor @Observable
final class ProjectModel {
    enum Resource: Equatable, Sendable { case changes, file, diff }
    var filePath: String
    var resource = Resource.changes
    var entries: [ProjectChange] = []
    var content = ""
    var truncated = false
    var busy = false
    var error: String?
    private let reads = ReadRequestOwner()
    private var readsEnabled = true
    private let read: @Sendable (String, [String: String]) async throws -> TextFileSnapshot
    private let list: @Sendable () async throws -> [ProjectChange]
    init(initialPath: String = "", read: @escaping @Sendable (String, [String: String]) async throws -> TextFileSnapshot, list: @escaping @Sendable () async throws -> [ProjectChange]) {
        filePath = initialPath; resource = initialPath.isEmpty ? .changes : .file; self.read = read; self.list = list
    }
    convenience init(session: SessionDescriptor, client: RemoteClient, initialPath: String = "") {
        self.init(initialPath: initialPath, read: { resource, query in
            try await client.get("/v1/sessions/\(session.id)/\(resource)", query: query, as: TextFileSnapshot.self)
        }, list: {
            let value = try await client.get("/v1/sessions/\(session.id)/changes", as: JSONValue.self)
            return ProjectChange.parse(entries: value["entries"].array ?? [])
        })
    }
    func suspendReads() { readsEnabled = false; reads.suspend(); busy = false }
    func resumeReads() { readsEnabled = true }
    func reload() async { await load(resource) }
    func load(_ resource: Resource) async {
        guard readsEnabled else { return }
        await reads.run { [self] request in
            busy = true; error = nil
            let path = filePath
            self.resource = resource; content = ""; entries = []; truncated = false
            defer { if reads.revision == request { busy = false } }
            do {
                switch resource {
                case .changes:
                    let value = try await list(); guard reads.isCurrent(request) else { return }
                    entries = value; content = ""; truncated = false
                case .file, .diff:
                    let value = try await read(resource == .file ? "file" : "diff", path.isEmpty && resource == .diff ? [:] : ["path": path])
                    guard reads.isCurrent(request) else { return }; content = value.text; truncated = value.truncated
                }
                self.resource = resource
            } catch { if reads.isCurrent(request) { self.error = ErrorPresentation().message(error) } }
        }
    }
}

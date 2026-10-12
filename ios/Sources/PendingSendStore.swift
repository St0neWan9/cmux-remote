import Foundation
import Darwin
import CmuxRemoteCore

/// Keeps an unresolved send in device-local protected storage before dispatch.
actor PendingSendStore {
    private let directory: URL
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PendingSends")
    }
    func load(scope: String, sessionID: String) throws -> SendRequest? {
        let file = file(scope: scope, sessionID: sessionID)
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else { throw failure() }
            let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
            var bytes = Data()
            while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
                guard bytes.count + chunk.count <= 1_048_576 else { throw failure() }
                bytes.append(chunk)
            }
            return try JSONDecoder().decode(SendRequest.self, from: bytes)
        } catch let error as CocoaError where [.fileNoSuchFile, .fileReadNoSuchFile].contains(error.code) {
            return nil
        } catch { throw failure() }
    }
    func save(_ request: SendRequest?, scope: String, sessionID: String) throws {
        let file = file(scope: scope, sessionID: sessionID)
        do {
            if let request {
                let bytes = try JSONEncoder().encode(request)
                guard bytes.count <= 1_048_576 else { throw failure() }
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                guard (try FileManager.default.attributesOfItem(atPath: directory.path))[.type] as? FileAttributeType == .typeDirectory else { throw failure() }
                if !FileManager.default.fileExists(atPath: file.path) {
                    let entries = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                    guard entries.count < 128 else { throw failure() }
                }
                #if os(iOS)
                try bytes.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
                #else
                try bytes.write(to: file, options: .atomic)
                #endif
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                let handle = try FileHandle(forWritingTo: file); defer { try? handle.close() }
                try handle.synchronize()
                var settings = URLResourceValues(); settings.isExcludedFromBackup = true
                var root = directory; try root.setResourceValues(settings)
            } else if FileManager.default.fileExists(atPath: file.path) {
                try FileManager.default.removeItem(at: file)
            } else { return }
            let descriptor = open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            guard descriptor >= 0 else { throw failure() }
            defer { close(descriptor) }
            guard fsync(descriptor) == 0 else { throw failure() }
        } catch { throw failure() }
    }
    private func file(scope: String, sessionID: String) -> URL {
        let key = IdentityCryptography().digest((try? JSONEncoder().encode([scope, sessionID])) ?? Data())
        return directory.appendingPathComponent(key + ".json")
    }
    private func failure() -> BridgeError {
        BridgeError("draft_storage_failed", "The unresolved send could not be saved or restored. Inspect the conversation before sending again.", status: 503)
    }
}

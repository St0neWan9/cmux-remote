import Foundation
import CmuxRemoteCore

/// Reads a relay's host directory; the relay is not trusted, so every entry is verified like a scanned QR.
public struct RelayDirectoryClient: Sendable {
    private let delegate: (any URLSessionDelegate & Sendable)?
    public init() { delegate = nil }
    init(delegate: any URLSessionDelegate & Sendable) { self.delegate = delegate }
    public func hosts(origin: String, now: Int = Int(Date().timeIntervalSince1970)) async throws -> [SignedValue<EnrollmentBootstrap>] {
        let canonical = try RelayOrigin(origin)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20; configuration.httpShouldSetCookies = false; configuration.urlCache = nil
        let session = URLSession(configuration: configuration, delegate: delegate ?? RelaySessionDelegate(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(from: canonical.directoryURL())
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 1_048_576,
              let hosts = try? JSONDecoder().decode([String: [String]].self, from: data)["hosts"], hosts.count <= 64 else {
            throw BridgeError("relay_unavailable", "The relay directory is unavailable.", status: 502)
        }
        var latest: [String: SignedValue<EnrollmentBootstrap>] = [:]
        for encoded in hosts {
            // A malformed or forged entry is skipped; it cannot hide other hosts.
            guard let bytes = Data(base64Encoded: encoded), bytes.count <= 8192,
                  let entry = try? JSONDecoder().decode(SignedValue<EnrollmentBootstrap>.self, from: bytes),
                  (try? EnrollmentLinkCodec().validate(entry, now: now)) != nil,
                  entry.value.endpoint.relay?.origin == canonical.value else { continue }
            if let existing = latest[entry.value.host.id], existing.value.expiresAt >= entry.value.expiresAt { continue }
            latest[entry.value.host.id] = entry
        }
        return latest.values.sorted { $0.value.host.name.localizedStandardCompare($1.value.host.name) == .orderedAscending }
    }
}

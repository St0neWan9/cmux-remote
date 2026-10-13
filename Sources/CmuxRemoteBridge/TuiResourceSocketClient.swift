import Foundation
import Darwin
import CmuxRemoteCore

/// Bounded, cancellable cmux.protocol/2 exchanges; never starts or upgrades a daemon.
public struct TuiResourceSocketClient: TuiResourceRequesting {
    private let path: String
    private let timeout: Duration
    private let requestID: @Sendable () -> String
    public init(path: String, timeout: Duration = .seconds(8), requestID: @escaping @Sendable () -> String = { UUID().uuidString }) { self.path = path; self.timeout = timeout; self.requestID = requestID }
    public func resource(_ operation: String, params: [String: JSONValue], idempotencyKey: String? = nil) async throws -> JSONValue {
        let id = requestID()
        var envelope: [String: JSONValue] = ["protocol": .string("cmux.protocol/2"), "type": .string("request"), "id": .string(id), "operation": .string(operation), "params": .object(params)]
        if let idempotencyKey { envelope["idempotency_key"] = .string(idempotencyKey) }
        var bytes = try JSONEncoder().encode(JSONValue.object(envelope)); bytes.append(10)
        guard bytes.count <= 1_048_576 else { throw BridgeError("too_large", "The daemon request exceeds the transfer limit.", status: 413) }
        let path = path, timeout = timeout, requestBytes = bytes
        let task = Task.detached { try Self.exchange(path: path, bytes: requestBytes, timeout: timeout) }
        let raw = try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
        guard let reply = try? JSONDecoder().decode(JSONValue.self, from: raw), reply["protocol"].string == "cmux.protocol/2", reply["type"].string == "response", reply["id"].string == id else {
            throw BridgeError("invalid_response", "The daemon returned an incompatible or unrelated response.", status: 502)
        }
        guard reply["ok"].bool == true else {
            let code: String
            switch reply["error"]["code"].string {
            case "selector.not_found", "selector.wrong_parent", "revision.conflict", "revision.stale": code = "stale_binding"
            case "mutation.indeterminate", "idempotency.conflict": code = "outcome_unknown"
            case "operation.unsupported", "protocol.unsupported": code = "unsupported"
            default: code = "socket_denied"
            }
            throw BridgeError(code, "The daemon could not confirm this resource operation.", status: 409)
        }
        return reply["result"]
    }
    private static func exchange(path: String, bytes: Data, timeout: Duration) throws -> Data {
        try Task.checkCancellation()
        guard path.hasPrefix("/"), !path.contains("\0") else { throw BridgeError("invalid_socket", "Use an absolute daemon socket path.") }
        var metadata = stat()
        guard lstat(path, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFSOCK, metadata.st_uid == getuid(), metadata.st_mode & 0o077 == 0 else {
            throw BridgeError("socket_unavailable", "Select an existing private same-user daemon socket.", status: 503)
        }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw BridgeError("socket_unavailable", "The local daemon socket could not be opened.", status: 503) }
        defer { Darwin.close(fd) }
        guard fcntl(fd, F_SETFL, O_NONBLOCK) == 0 else { throw BridgeError("socket_unavailable", "The daemon transport could not be configured.") }
        var noPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noPipe, socklen_t(MemoryLayout<Int32>.size))
        var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
        let pathname = Array(path.utf8) + [0]
        guard pathname.count <= MemoryLayout.size(ofValue: address.sun_path) else { throw BridgeError("invalid_socket", "The daemon socket path is too long.") }
        withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: pathname) }
        let deadline = ContinuousClock().now.advanced(by: timeout)
        let connected = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
        if connected != 0 {
            guard [EINPROGRESS, EAGAIN, EWOULDBLOCK].contains(errno) else { throw BridgeError("socket_unavailable", "The local daemon is unavailable.", status: 503) }
            try ready(fd, events: Int16(POLLOUT), deadline: deadline)
            var error: Int32 = 0, length = socklen_t(MemoryLayout<Int32>.size)
            guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &error, &length) == 0, error == 0 else { throw BridgeError("socket_unavailable", "The local daemon is unavailable.", status: 503) }
        }
        var uid: uid_t = 0, gid: gid_t = 0
        guard getpeereid(fd, &uid, &gid) == 0, uid == getuid() else { throw BridgeError("socket_denied", "The daemon belongs to another local user.", status: 403) }
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                try ready(fd, events: Int16(POLLOUT), deadline: deadline)
                let count = Darwin.send(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset, 0)
                if count < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
                guard count > 0 else { throw BridgeError("outcome_unknown", "The daemon request was not confirmed.", status: 504) }
                offset += count
            }
        }
        var reply = Data(), buffer = [UInt8](repeating: 0, count: 8192)
        while reply.count < 8_388_608 {
            try ready(fd, events: Int16(POLLIN), deadline: deadline)
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            if count < 0 && [EINTR, EAGAIN, EWOULDBLOCK].contains(errno) { continue }
            guard count > 0 else { throw BridgeError("outcome_unknown", "The daemon response was lost; inspect before repeating input.", status: 504) }
            reply.append(contentsOf: buffer.prefix(count))
            if let end = reply.firstIndex(of: 10) { return Data(reply[..<end]) }
        }
        throw BridgeError("too_large", "The daemon response exceeds the transfer limit.", status: 413)
    }
    private static func ready(_ fd: Int32, events: Int16, deadline: ContinuousClock.Instant) throws {
        while true {
            try Task.checkCancellation()
            guard ContinuousClock().now < deadline else { throw BridgeError("outcome_unknown", "The daemon exchange timed out.", status: 504) }
            var descriptor = pollfd(fd: fd, events: events, revents: 0)
            let result = Darwin.poll(&descriptor, 1, 100)
            if result > 0 { return }
            if result < 0 && errno != EINTR { throw BridgeError("outcome_unknown", "The daemon transport closed.", status: 504) }
        }
    }
}

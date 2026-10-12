import Foundation
import Darwin
import CmuxRemoteCore

/// Bounded newline RPC over cmux's existing owner-controlled Unix socket.
public struct UnixSocketClient: CmuxControlling {
    private let path: String
    private let password: String?
    public init(path: String, password: String? = nil) { self.path = path; self.password = password }

    public func request(_ method: String, params: [String: JSONValue] = [:]) async throws -> JSONValue {
        let path = path; let password = password
        return try await Task.detached {
            let fd = socket(AF_UNIX, SOCK_STREAM, 0)
            guard fd >= 0 else { throw BridgeError("socket_unavailable", "Could not open the cmux socket.", status: 503) }
            defer { Darwin.close(fd) }
            var timeout = timeval(tv_sec: 8, tv_usec: 0)
            _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var noSIGPIPE: Int32 = 1
            _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSIGPIPE, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_un(); address.sun_family = sa_family_t(AF_UNIX)
            let bytes = Array(path.utf8) + [0]
            guard bytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
                throw BridgeError("invalid_socket", "The socket path is too long.")
            }
            withUnsafeMutableBytes(of: &address.sun_path) { target in target.copyBytes(from: bytes) }
            let connected = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
            }
            guard connected == 0 else { throw BridgeError("socket_unavailable", "Open cmux and check its socket access policy.", status: 503) }
            if let password {
                guard !password.contains("\n"), !password.contains("\r"), password.utf8.count <= 4096 else { throw BridgeError("invalid_password", "The local socket password is invalid.") }
                // Match cmux CLI's local password handshake; this is not cloud auth.login.
                try Self.writeData(Data(("auth " + password + "\n").utf8), fd: fd)
                let reply = try Self.readLine(fd: fd)
                guard String(decoding: reply, as: UTF8.self).hasPrefix("OK") else { throw BridgeError("socket_denied", "cmux rejected socket authentication.", status: 403) }
            }
            try Self.write(.object(["id": .string(UUID().uuidString), "method": .string(method), "params": .object(params)]), fd: fd)
            let reply = try Self.read(fd: fd)
            guard reply["ok"].bool == true else {
                throw BridgeError(reply["error"]["code"].string ?? "socket_denied", "cmux could not complete this operation.", status: 502)
            }
            return reply["result"]
        }.value
    }

    private static func write(_ value: JSONValue, fd: Int32) throws {
        var data = try JSONEncoder().encode(value); data.append(10)
        try writeData(data, fd: fd)
    }
    private static func writeData(_ data: Data, fd: Int32) throws {
        guard data.count <= 1_048_576 else { throw BridgeError("too_large", "The request is too large.", status: 413) }
        try data.withUnsafeBytes { raw in
            var offset = 0
            while offset < raw.count {
                let n = Darwin.send(fd, raw.baseAddress!.advanced(by: offset), raw.count - offset, 0)
                guard n > 0 else { throw BridgeError("outcome_unknown", "The connection closed; inspect the task before trying again.", status: 504) }
                offset += n
            }
        }
    }

    private static func read(fd: Int32) throws -> JSONValue {
        // Preserve transport failure so read-only callers can reconnect. Only a
        // received, undecodable response is invalid_response; writes still have
        // unknown outcomes and must not acquire an automatic retry.
        let data = try readLine(fd: fd)
        guard let value = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            throw BridgeError("invalid_response", "cmux returned an invalid response.", status: 502)
        }
        return value
    }
    private static func readLine(fd: Int32) throws -> Data {
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 8192)
        while data.count < 8_388_608 {
            let count = Darwin.recv(fd, &buffer, buffer.count, 0)
            guard count > 0 else { throw BridgeError("outcome_unknown", "The response was lost; inspect the task before trying again.", status: 504) }
            data.append(contentsOf: buffer.prefix(count))
            if let end = data.firstIndex(of: 10) {
                return Data(data[..<end])
            }
        }
        throw BridgeError("too_large", "The cmux response exceeds the read limit.", status: 413)
    }
}

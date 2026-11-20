import Foundation
import Darwin

/// Prefers an active private IPv4 address on Ethernet/Wi-Fi over loopback and VPN interfaces.
public struct LANAddressResolver: Sendable {
    public init() {}
    public func address() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return nil }
        defer { freeifaddrs(head) }
        var candidates: [(String, String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = head
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let item = current.pointee
            guard let address = item.ifa_addr, address.pointee.sa_family == AF_INET,
                  item.ifa_flags & UInt32(IFF_UP) != 0, item.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(MemoryLayout<sockaddr_in>.size), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let value = String(cString: host); let name = String(cString: item.ifa_name)
            let octets = value.split(separator: ".").compactMap { Int($0) }
            guard octets.count == 4, octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && (16...31).contains(octets[1])) else { continue }
            candidates.append((name, value))
        }
        return candidates.sorted { ($0.0.hasPrefix("en") ? 0 : 1, $0.0) < ($1.0.hasPrefix("en") ? 0 : 1, $1.0) }.first?.1
    }
}

import Foundation

/// How the Bridge proves its relay socket still reaches Cloudflare. Protocol pings are answered by the edge
/// without waking the relay, so liveness costs no billable messages.
public struct CloudRelayLiveness: Sendable {
    /// Idle time between pings; well under the idle timeouts of NATs and proxies on the path.
    public let pingInterval: Duration
    /// A path that silently died never answers, and the socket alone may not report it.
    public let pongDeadline: Duration
    /// Time for the relay to acknowledge registration before the dial is abandoned.
    public let readyDeadline: Duration
    public init(pingInterval: Duration = .seconds(25), pongDeadline: Duration = .seconds(10), readyDeadline: Duration = .seconds(15)) {
        self.pingInterval = pingInterval; self.pongDeadline = pongDeadline; self.readyDeadline = readyDeadline
    }
}

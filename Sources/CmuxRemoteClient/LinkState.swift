/// Whether the phone currently holds a working link to its Mac.
public enum LinkState: Sendable, Equatable {
    /// Dialing: the LAN address first, then the relay.
    case connecting
    case connected
    /// The last attempt or the open link failed; the next request or a reconnect dials again.
    case disconnected
}

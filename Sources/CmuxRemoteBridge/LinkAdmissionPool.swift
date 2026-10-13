import Foundation

/// Caps upgraded LAN connections before unauthenticated handshakes allocate session state.
actor LinkAdmissionPool {
    private var channels: Set<ObjectIdentifier> = []
    private let maximum: Int
    init(maximum: Int = 20) { self.maximum = maximum }
    func reserve(_ channel: ObjectIdentifier) -> Bool {
        guard !channels.contains(channel), channels.count < maximum else { return false }
        channels.insert(channel); return true
    }
    func release(_ channel: ObjectIdentifier) { channels.remove(channel) }
}

/// What the app's connection supervision depends on; a change restarts it.
struct ConnectionSupervision: Hashable {
    let active: Bool
    let hosts: [String]
}

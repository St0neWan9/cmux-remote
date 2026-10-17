import Foundation

/// The owner-protocol revision a resident reports through `bridge.status`.
///
/// The Mac launcher adopts an already-running resident instead of spawning its own; one that
/// predates this revision cannot answer the owner methods the bundled companion requires, so
/// the launcher replaces it instead of adopting it. Bump this whenever the owner protocol
/// gains behavior a bundled companion requires.
public enum OwnerRevision {
    public static let current = 1
}

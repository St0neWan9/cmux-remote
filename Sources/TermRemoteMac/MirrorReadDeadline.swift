import Foundation

/// Caps one remote read below the private owner-channel timeout and cancels the losing task.
struct MirrorReadDeadline: Sendable {
    var timeout: Duration = .seconds(4)
    func run<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let timeout = timeout
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask { try await Task.sleep(for: timeout); throw URLError(.timedOut) }
            defer { group.cancelAll() }
            guard let result = try await group.next() else { throw CancellationError() }
            return result
        }
    }
}

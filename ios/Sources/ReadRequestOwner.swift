import Foundation

/// Cancels obsolete reads and rejects completions from uncooperative transports.
@MainActor final class ReadRequestOwner {
    private(set) var revision = UUID()
    private var task: Task<Void, Never>?
    func isCurrent(_ request: UUID) -> Bool { revision == request && !Task.isCancelled }
    func suspend() { revision = UUID(); task?.cancel(); task = nil }
    func run(_ operation: @escaping @MainActor (UUID) async -> Void) async {
        guard !Task.isCancelled else { return }
        suspend()
        let request = revision
        let active = Task { @MainActor in
            guard !Task.isCancelled else { return }
            await operation(request)
        }
        task = active
        await withTaskCancellationHandler { await active.value } onCancel: { active.cancel() }
        if revision == request { task = nil }
    }
}

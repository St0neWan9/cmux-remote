import Foundation

/// Places owned remote projections inside cmux's native workspace sidebar.
public protocol NativeRemoteWorkspaceGrouping: Sendable {
    /// Keeps existing local rows and places the Remote section after them.
    func place(workspaceID: String, windowID: String?) async throws
}

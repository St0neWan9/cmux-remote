import Foundation

/// The Rex server's default local control socket.
public enum RexSocketLocation {
    public static func path(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        home.appendingPathComponent("Library/Application Support/rex/server.sock").path
    }

    public static func isAvailable(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Bool {
        FileManager.default.fileExists(atPath: path(home: home))
    }
}

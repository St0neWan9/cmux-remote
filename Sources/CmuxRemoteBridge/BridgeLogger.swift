import os

extension Logger {
    static let relay = Logger(subsystem: "com.st0newan9.cmux-remote.mac", category: "relay")
    static let link  = Logger(subsystem: "com.st0newan9.cmux-remote.mac", category: "link")
}

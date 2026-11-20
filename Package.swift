// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "term-remote",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "term-remote", targets: ["TermRemoteCLI"]),
        .library(name: "TermRemoteClient", targets: ["TermRemoteClient"]),
        .library(name: "TermRemoteMac", targets: ["TermRemoteMac"]),
        .library(name: "TermRemoteBridge", targets: ["TermRemoteBridge"]),
        .library(name: "TermRemoteCore", targets: ["TermRemoteCore"])
    ],
    dependencies: [
        .package(path: "Vendor/CmuxAgentChat"),
        .package(path: "Vendor/CmuxTerminalReplay"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.35.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.11.2")
    ],
    targets: [
        .target(name: "TermRemoteCore", dependencies: [.product(name: "CmuxAgentChat", package: "CmuxAgentChat")]),
        .target(name: "CBridgeDiscovery"),
        .target(name: "TermRemoteBridge", dependencies: ["TermRemoteCore", "CBridgeDiscovery", .product(name: "SwiftTerm", package: "SwiftTerm"), .product(name: "CmuxTerminalReplay", package: "CmuxTerminalReplay"), .product(name: "NIOCore", package: "swift-nio"), .product(name: "NIOPosix", package: "swift-nio"), .product(name: "NIOHTTP1", package: "swift-nio"), .product(name: "NIOWebSocket", package: "swift-nio"), .product(name: "NIOSSL", package: "swift-nio-ssl")]),
        .target(name: "TermRemoteClient", dependencies: ["TermRemoteCore"]),
        .target(name: "TermRemoteMac", dependencies: ["TermRemoteCore", "TermRemoteClient", "TermRemoteBridge"]),
        .executableTarget(name: "TermRemoteCLI", dependencies: ["TermRemoteBridge", "TermRemoteMac", "TermRemoteClient"]),
        .testTarget(name: "TermRemoteTests", dependencies: ["TermRemoteCore", "TermRemoteBridge", "TermRemoteClient", "TermRemoteMac", .product(name: "CmuxTerminalReplay", package: "CmuxTerminalReplay")])
    ],
    swiftLanguageModes: [.v6]
)

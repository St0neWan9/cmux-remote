// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "cmux-remote",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .executable(name: "cmux-remote", targets: ["CmuxRemoteCLI"]),
        .library(name: "CmuxRemoteClient", targets: ["CmuxRemoteClient"]),
        .library(name: "CmuxRemoteCore", targets: ["CmuxRemoteCore"])
    ],
    dependencies: [
        .package(path: "Vendor/CmuxAgentChat"),
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-nio-ssl.git", from: "2.35.0")
    ],
    targets: [
        .target(name: "CmuxRemoteCore", dependencies: [.product(name: "CmuxAgentChat", package: "CmuxAgentChat")]),
        .target(name: "CmuxRemoteBridge", dependencies: ["CmuxRemoteCore", .product(name: "NIOCore", package: "swift-nio"), .product(name: "NIOPosix", package: "swift-nio"), .product(name: "NIOHTTP1", package: "swift-nio"), .product(name: "NIOSSL", package: "swift-nio-ssl")]),
        .target(name: "CmuxRemoteClient", dependencies: ["CmuxRemoteCore"]),
        .executableTarget(name: "CmuxRemoteCLI", dependencies: ["CmuxRemoteBridge"]),
        .testTarget(name: "CmuxRemoteTests", dependencies: ["CmuxRemoteCore", "CmuxRemoteBridge", "CmuxRemoteClient"])
    ],
    swiftLanguageModes: [.v6]
)

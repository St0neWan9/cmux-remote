// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CmuxAgentChat", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "CmuxAgentChat", targets: ["CmuxAgentChat"])], targets: [.target(name: "CmuxAgentChat", swiftSettings: [.swiftLanguageMode(.v6)])])

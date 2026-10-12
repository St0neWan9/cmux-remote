// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CmuxTerminalReplay", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "CmuxTerminalReplay", targets: ["CmuxTerminalReplay"])], targets: [.target(name: "CmuxTerminalReplay")], swiftLanguageModes: [.v6])

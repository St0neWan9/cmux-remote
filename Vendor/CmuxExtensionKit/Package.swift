// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "CmuxExtensionKit", platforms: [.macOS(.v14), .iOS(.v17)], products: [.library(name: "CmuxExtensionKit", targets: ["CmuxExtensionKit"])], targets: [.target(name: "CmuxExtensionKit")], swiftLanguageModes: [.v6])

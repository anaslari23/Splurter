// swift-tools-version:6.0
import PackageDescription
let package = Package(
    name: "Splurter",
    platforms: [.macOS(.v15)],
    targets: [.executableTarget(name: "Splurter", path: "Sources/Splurter")],
    swiftLanguageModes: [.v5]
)

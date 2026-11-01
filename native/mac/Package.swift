// swift-tools-version:5.9
import PackageDescription
let package = Package(
    name: "Splurter",
    platforms: [.macOS(.v13)],
    targets: [.executableTarget(name: "Splurter", path: "Sources/Splurter")]
)

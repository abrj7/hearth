// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Hearth",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Hearth", path: "Sources/Hearth")
    ]
)

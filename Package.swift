// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Vinyl",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Vinyl", path: "Sources/Vinyl")
    ]
)

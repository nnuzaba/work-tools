// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "PRWatch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "PRWatch", path: "Sources/PRWatch")
    ]
)

// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "MacShuttleSwift",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "MacShuttle", targets: ["MacShuttleSwift"])
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "MacShuttleSwift",
            dependencies: [],
            path: "Sources/MacShuttleSwift"
        )
    ]
)

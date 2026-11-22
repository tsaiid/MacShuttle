// swift-tools-version: 5.5
import PackageDescription

let package = Package(
    name: "MacShuttleSwift",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(name: "MacShuttle", targets: ["MacShuttle"])
    ],
    dependencies: [],
    targets: [
        .target(
            name: "MacShuttleCore",
            dependencies: [],
            path: "Sources/MacShuttleCore"
        ),
        .executableTarget(
            name: "MacShuttle",
            dependencies: ["MacShuttleCore"],
            path: "Sources/MacShuttle"
        ),
        .testTarget(
            name: "MacShuttleTests",
            dependencies: ["MacShuttleCore"],
            path: "Tests/MacShuttleTests"
        )
    ]
)

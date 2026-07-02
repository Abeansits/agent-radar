// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "agent-doodle",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Local path during development (Arthur uses the same fork/branch).
        // Swap to remote url + branch when publishing.
        .package(path: "../DynamicNotchKit"),
    ],
    targets: [
        .target(
            name: "DoodleCore",
            dependencies: [],
            path: "Sources/DoodleCore"
        ),
        .executableTarget(
            name: "doodle",
            dependencies: ["DoodleCore"],
            path: "Sources/DoodleCLI"
        ),
        .executableTarget(
            name: "DoodleNotchApp",
            dependencies: [
                "DoodleCore",
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit"),
            ],
            path: "Sources/DoodleNotchApp"
        ),
        .testTarget(
            name: "DoodleCoreTests",
            dependencies: ["DoodleCore"],
            path: "Tests/DoodleCoreTests"
        )
    ]
)

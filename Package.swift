// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "agent-doodle",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Same as Arthur: branch on the Abeansits fork (configurable animations support).
        .package(url: "https://github.com/Abeansits/DynamicNotchKit", branch: "feature/configurable-animations"),
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

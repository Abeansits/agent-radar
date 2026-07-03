// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "agent-radar",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        // Same as Arthur: branch on the Abeansits fork (configurable animations support).
        .package(url: "https://github.com/Abeansits/DynamicNotchKit", branch: "feature/configurable-animations"),
    ],
    targets: [
        .target(
            name: "RadarCore",
            dependencies: [],
            path: "Sources/RadarCore"
        ),
        .executableTarget(
            name: "radar",
            dependencies: ["RadarCore"],
            path: "Sources/RadarCLI"
        ),
        .executableTarget(
            name: "RadarNotchApp",
            dependencies: [
                "RadarCore",
                .product(name: "DynamicNotchKit", package: "DynamicNotchKit"),
            ],
            path: "Sources/RadarNotchApp"
        ),
        .testTarget(
            name: "RadarCoreTests",
            dependencies: ["RadarCore"],
            path: "Tests/RadarCoreTests"
        )
    ]
)

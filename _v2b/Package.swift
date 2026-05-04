// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Blocker",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "BlockerCore", targets: ["BlockerCore"])
    ],
    targets: [
        .target(
            name: "BlockerCore",
            path: "blocker/Core"
        ),
        .executableTarget(
            name: "BlockerCoreSpec",
            dependencies: ["BlockerCore"],
            path: "BlockerCoreSpec"
        )
    ]
)

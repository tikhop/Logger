// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Logger",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "Logger",
            targets: ["Logger"])
    ],
    dependencies: [
    ],
    targets: [
        .target(
            name: "Logger",
            dependencies: [
            ],
            path: "Sources",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        ),
        .testTarget(
            name: "LoggerTests",
            dependencies: ["Logger"],
            path: "Tests",
            swiftSettings: [
                .enableExperimentalFeature("StrictConcurrency")
            ]
        )
    ]
)

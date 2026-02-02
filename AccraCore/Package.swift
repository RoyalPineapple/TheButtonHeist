// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AccraCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AccraCore", targets: ["AccraCore"]),
        // AccraHost with auto-start: includes both Swift implementation and ObjC loader
        .library(name: "AccraHost", targets: ["AccraHost", "AccraHostLoader"]),
        // AccraHostCore: Swift implementation only, manual start required
        .library(name: "AccraHostCore", targets: ["AccraHost"]),
        .library(name: "AccraClient", targets: ["AccraClient"])
    ],
    dependencies: [
        .package(path: "../AccessibilitySnapshot")
    ],
    targets: [
        .target(
            name: "AccraCore",
            path: "Sources/AccraCore"
        ),
        // Swift implementation of AccraHost
        .target(
            name: "AccraHost",
            dependencies: [
                "AccraCore",
                .product(name: "AccessibilitySnapshotParser", package: "AccessibilitySnapshot")
            ],
            path: "Sources/AccraHost"
        ),
        // Objective-C loader that triggers auto-start via +load
        .target(
            name: "AccraHostLoader",
            dependencies: ["AccraHost"],
            path: "Sources/AccraHostLoader",
            publicHeadersPath: "include"
        ),
        .target(
            name: "AccraClient",
            dependencies: ["AccraCore"],
            path: "Sources/AccraClient"
        ),
        .testTarget(
            name: "AccraCoreTests",
            dependencies: ["AccraCore"],
            path: "Tests/AccraCoreTests"
        )
    ]
)

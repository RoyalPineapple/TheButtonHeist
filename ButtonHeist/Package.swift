// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ButtonHeist",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TheScore", targets: ["TheScore"]),
        // InsideJob with auto-start: includes both Swift implementation and ObjC loader
        .library(name: "InsideJob", targets: ["InsideJob", "ThePlant"]),
        .library(name: "Wheelman", targets: ["Wheelman"]),
        .library(name: "ButtonHeist", targets: ["ButtonHeist"])
    ],
    dependencies: [
        .package(path: "../AccessibilitySnapshot")
    ],
    targets: [
        .target(
            name: "TheScore",
            path: "Sources/TheScore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Swift implementation of InsideJob
        .target(
            name: "InsideJob",
            dependencies: [
                "TheScore",
                "Wheelman",
                .product(name: "AccessibilitySnapshotParser", package: "AccessibilitySnapshot")
            ],
            path: "Sources/InsideJob",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Objective-C loader that triggers auto-start via +load
        .target(
            name: "ThePlant",
            dependencies: ["InsideJob"],
            path: "Sources/ThePlant",
            publicHeadersPath: "include"
        ),
        .target(
            name: "Wheelman",
            dependencies: ["TheScore"],
            path: "Sources/Wheelman",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "ButtonHeist",
            dependencies: ["TheScore", "Wheelman"],
            path: "Sources/ButtonHeist",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TheScoreTests",
            dependencies: ["TheScore"],
            path: "Tests/TheScoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

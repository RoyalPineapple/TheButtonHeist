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
        // TheInsideJob with auto-start: includes both Swift implementation and ObjC loader
        .library(name: "TheInsideJob", targets: ["TheInsideJob", "ThePlant"]),
        .library(name: "TheGetaway", targets: ["TheGetaway"]),
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
        // Swift implementation of TheInsideJob
        .target(
            name: "TheInsideJob",
            dependencies: [
                "TheScore",
                "TheGetaway",
                .product(name: "AccessibilitySnapshotParser", package: "AccessibilitySnapshot")
            ],
            path: "Sources/TheInsideJob",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Objective-C loader that triggers auto-start via +load
        .target(
            name: "ThePlant",
            dependencies: ["TheInsideJob"],
            path: "Sources/ThePlant",
            publicHeadersPath: "include"
        ),
        .target(
            name: "TheGetaway",
            dependencies: ["TheScore"],
            path: "Sources/TheGetaway",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "ButtonHeist",
            dependencies: ["TheScore"],
            path: "Sources/TheButtonHeist",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TheScoreTests",
            dependencies: ["TheScore"],
            path: "Tests/TheScoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ButtonHeistTests",
            dependencies: ["ButtonHeist", "TheScore", "TheGetaway"],
            path: "Tests/ButtonHeistTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TheInsideJobTests",
            dependencies: ["TheInsideJob", "TheScore"],
            path: "Tests/TheInsideJobTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)

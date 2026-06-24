// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ButtonHeist",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "ThePlans", targets: ["ThePlans"]),
        .library(name: "TheScore", targets: ["TheScore"]),
        .library(name: "ButtonHeistDSL", targets: ["ButtonHeistDSL"]),
        .executable(name: "heist-plan", targets: ["HeistPlanTool"]),
        .executable(name: "heist-doctor", targets: ["HeistDoctorTool"]),
        // TheInsideJob with auto-start: includes both Swift implementation and ObjC loader
        .library(name: "TheInsideJob", targets: ["TheInsideJob", "ThePlant"]),
        .library(name: "ButtonHeist", targets: ["ButtonHeist"])
    ],
    dependencies: [
        // Parser semantics are part of Button Heist's release contract.
        // Keep this exact tag aligned with submodules/AccessibilitySnapshotBH
        // via scripts/check-parser-contract.sh and scripts/bump-parser.sh.
        .package(url: "https://github.com/RoyalPineapple/AccessibilitySnapshotBH", exact: "0.16.2"),
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.7.0")),
    ],
    targets: [
        .target(
            name: "ThePlans",
            dependencies: [],
            path: "ButtonHeist/Sources/ThePlans",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "TheScore",
            dependencies: [
                "ThePlans",
                .product(name: "AccessibilitySnapshotModel", package: "AccessibilitySnapshotBH"),
            ],
            path: "ButtonHeist/Sources/TheScore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "ButtonHeistDSL",
            dependencies: ["ThePlans"],
            path: "ButtonHeist/Sources/ButtonHeistDSL",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "HeistPlanTool",
            dependencies: [
                "ThePlans",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "ButtonHeist/Sources/HeistPlanTool",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "HeistDoctorCore",
            dependencies: [
                "ThePlans",
                "TheScore",
            ],
            path: "ButtonHeist/Sources/HeistDoctorCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "HeistDoctorTool",
            dependencies: [
                "HeistDoctorCore",
                "TheScore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "ButtonHeist/Sources/HeistDoctorTool",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Swift implementation of TheInsideJob
        .target(
            name: "TheInsideJob",
            dependencies: [
                "ThePlans",
                "TheScore",
                .product(
                    name: "AccessibilitySnapshotParser",
                    package: "AccessibilitySnapshotBH",
                    condition: .when(platforms: [.iOS])
                ),
            ],
            path: "ButtonHeist/Sources/TheInsideJob",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Objective-C loader that triggers auto-start via +load
        .target(
            name: "ThePlant",
            dependencies: ["TheInsideJob"],
            path: "ButtonHeist/Sources/ThePlant",
            publicHeadersPath: "include"
        ),
        .target(
            name: "ButtonHeist",
            dependencies: [
                "ThePlans",
                "TheScore",
                .product(name: "AccessibilitySnapshotModel", package: "AccessibilitySnapshotBH"),
            ],
            path: "ButtonHeist/Sources/TheButtonHeist",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "ThePlansTests",
            dependencies: ["ThePlans"],
            path: "ButtonHeist/Tests/ThePlansTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "HeistDoctorCoreTests",
            dependencies: [
                "HeistDoctorCore",
                "TheScore",
                .product(name: "AccessibilitySnapshotModel", package: "AccessibilitySnapshotBH"),
            ],
            path: "ButtonHeist/Tests/HeistDoctorCoreTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)

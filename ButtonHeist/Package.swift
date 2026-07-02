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
        .executable(name: "buttonheist-docgen", targets: ["ButtonHeistDocGen"]),
        // TheInsideJob with auto-start: includes both Swift implementation and ObjC loader
        .library(name: "TheInsideJob", targets: ["TheInsideJob", "ThePlant"]),
        .library(name: "ButtonHeistTesting", targets: ["ButtonHeistTesting"]),
        .library(name: "ButtonHeist", targets: ["ButtonHeist"])
    ],
    dependencies: [
        .package(path: "../submodules/AccessibilitySnapshotBH"),
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.7.0")),
    ],
    targets: [
        .target(
            name: "ButtonHeistSupport",
            dependencies: [],
            path: "Sources/ButtonHeistSupport",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .target(
            name: "ThePlans",
            dependencies: [],
            path: "Sources/ThePlans",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .target(
            name: "TheScore",
            dependencies: [
                "ThePlans",
                .product(name: "AccessibilitySnapshotModel", package: "AccessibilitySnapshotBH"),
            ],
            path: "Sources/TheScore",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .target(
            name: "ButtonHeistDSL",
            dependencies: ["ThePlans"],
            path: "Sources/ButtonHeistDSL",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .executableTarget(
            name: "HeistPlanTool",
            dependencies: [
                "ThePlans",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/HeistPlanTool",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .target(
            name: "HeistDoctorCore",
            dependencies: [
                "ThePlans",
                "TheScore",
            ],
            path: "Sources/HeistDoctorCore",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .executableTarget(
            name: "HeistDoctorTool",
            dependencies: [
                "HeistDoctorCore",
                "TheScore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/HeistDoctorTool",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .executableTarget(
            name: "ButtonHeistDocGen",
            dependencies: [
                "ButtonHeist",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/ButtonHeistDocGen",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        // Swift implementation of TheInsideJob
        .target(
            name: "TheInsideJob",
            dependencies: [
                "ButtonHeistSupport",
                "ThePlans",
                "TheScore",
                .product(
                    name: "AccessibilitySnapshotParser",
                    package: "AccessibilitySnapshotBH",
                    condition: .when(platforms: [.iOS])
                ),
            ],
            path: "Sources/TheInsideJob",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        // Objective-C loader that triggers auto-start via +load
        .target(
            name: "ThePlant",
            dependencies: ["TheInsideJob"],
            path: "Sources/ThePlant",
            publicHeadersPath: "include"
        ),
        .target(
            name: "ButtonHeistTesting",
            dependencies: [
                "ButtonHeistDSL",
                "TheInsideJob",
            ],
            path: "Sources/ButtonHeistTesting",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .target(
            name: "ButtonHeist",
            dependencies: [
                "ButtonHeistSupport",
                "ThePlans",
                "TheScore",
                .product(name: "AccessibilitySnapshotModel", package: "AccessibilitySnapshotBH"),
            ],
            path: "Sources/TheButtonHeist",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .target(
            name: "ButtonHeistTestSupport",
            dependencies: [],
            path: "Tests/TestSupport",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "TheScoreTests",
            dependencies: ["ButtonHeistTestSupport", "ThePlans", "TheScore"],
            path: "Tests/TheScoreTests",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "ButtonHeistSupportTests",
            dependencies: ["ButtonHeistSupport"],
            path: "Tests/ButtonHeistSupportTests",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "ThePlansTests",
            dependencies: ["ThePlans"],
            path: "Tests/ThePlansTests",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "HeistDoctorCoreTests",
            dependencies: [
                "ButtonHeistTestSupport",
                "HeistDoctorCore",
                "TheScore",
                .product(name: "AccessibilitySnapshotModel", package: "AccessibilitySnapshotBH"),
            ],
            path: "Tests/HeistDoctorCoreTests",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "ButtonHeistDSLTests",
            dependencies: ["ButtonHeistDSL", "ThePlans", "TheScore"],
            path: "Tests/ButtonHeistDSLTests",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "ButtonHeistTests",
            dependencies: [
                "ButtonHeistTestSupport", "ButtonHeist", "ButtonHeistSupport", "ThePlans", "TheScore",
            ],
            path: "Tests/ButtonHeistTests",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "TheInsideJobTests",
            dependencies: [
                "ButtonHeistTestSupport", "ButtonHeistTesting", "TheInsideJob", "ThePlans", "TheScore",
            ],
            path: "Tests/TheInsideJobTests",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        )
    ]
)

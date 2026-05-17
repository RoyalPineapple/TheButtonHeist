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
        .library(name: "ButtonHeist", targets: ["ButtonHeist"])
    ],
    dependencies: [
        // Parser semantics are part of Button Heist's release contract.
        // Keep this exact tag aligned with submodules/AccessibilitySnapshotBH
        // via scripts/check-parser-contract.sh and scripts/bump-parser.sh.
        .package(url: "https://github.com/RoyalPineapple/AccessibilitySnapshotBH", exact: "0.8.0"),
        .package(url: "https://github.com/apple/swift-certificates", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "TheScore",
            path: "ButtonHeist/Sources/TheScore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Swift implementation of TheInsideJob
        .target(
            name: "TheInsideJob",
            dependencies: [
                "TheScore",
                .product(
                    name: "AccessibilitySnapshotParser",
                    package: "AccessibilitySnapshotBH",
                    condition: .when(platforms: [.iOS])
                ),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "ButtonHeist/Sources/TheInsideJob",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Objective-C loader that triggers auto-start via +load
        .target(
            name: "ThePlant",
            dependencies: [],
            path: "ButtonHeist/Sources/ThePlant",
            publicHeadersPath: "include"
        ),
        .target(
            name: "ButtonHeist",
            dependencies: [
                "TheScore",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "ButtonHeist/Sources/TheButtonHeist",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)

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
        .package(path: "../AccessibilitySnapshot"),
        .package(url: "https://github.com/apple/swift-certificates", from: "1.0.0"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "TheScore",
            path: "Sources/TheScore",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        // Swift implementation of TheInsideJob
        .target(
            name: "TheInsideJob",
            dependencies: [
                "TheScore",
                .product(name: "AccessibilitySnapshotParser", package: "AccessibilitySnapshot"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Crypto", package: "swift-crypto"),
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
            name: "ButtonHeist",
            dependencies: [
                "TheScore",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/TheButtonHeist",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "TheScoreTests",
            dependencies: ["TheScore"],
            path: "Tests/TheScoreTests",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "ButtonHeistTests",
            dependencies: [
                "ButtonHeist", "TheScore",
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Tests/ButtonHeistTests",
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-warnings-as-errors"])]
        ),
        .testTarget(
            name: "TheInsideJobTests",
            dependencies: ["TheInsideJob", "TheScore"],
            path: "Tests/TheInsideJobTests",
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-warnings-as-errors"])]
        )
    ]
)

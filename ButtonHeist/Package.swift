// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ButtonHeist",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TheGoods", targets: ["TheGoods"]),
        // InsideJob with auto-start: includes both Swift implementation and ObjC loader
        .library(name: "InsideJob", targets: ["InsideJob", "InsideJobLoader"]),
        .library(name: "Wheelman", targets: ["Wheelman"]),
        .library(name: "ButtonHeist", targets: ["ButtonHeist"])
    ],
    dependencies: [
        .package(path: "../AccessibilitySnapshot")
    ],
    targets: [
        .target(
            name: "TheGoods",
            path: "Sources/TheGoods",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Swift implementation of InsideJob
        .target(
            name: "InsideJob",
            dependencies: [
                "TheGoods",
                "Wheelman",
                .product(name: "AccessibilitySnapshotParser", package: "AccessibilitySnapshot")
            ],
            path: "Sources/InsideJob",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        // Objective-C loader that triggers auto-start via +load
        .target(
            name: "InsideJobLoader",
            dependencies: ["InsideJob"],
            path: "Sources/InsideJobLoader",
            publicHeadersPath: "include"
        ),
        .target(
            name: "Wheelman",
            dependencies: ["TheGoods"],
            path: "Sources/Wheelman",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .target(
            name: "ButtonHeist",
            dependencies: ["TheGoods", "Wheelman"],
            path: "Sources/ButtonHeist",
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TheGoodsTests",
            dependencies: ["TheGoods"],
            path: "Tests/TheGoodsTests",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)

// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ButtonHeist",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "TheGoods", targets: ["TheGoods"]),
        // InsideMan with auto-start: includes both Swift implementation and ObjC loader
        .library(name: "InsideMan", targets: ["InsideMan", "InsideManLoader"]),
        // InsideManCore: Swift implementation only, manual start required
        .library(name: "InsideManCore", targets: ["InsideMan"]),
        .library(name: "Wheelman", targets: ["Wheelman"])
    ],
    dependencies: [
        .package(path: "../AccessibilitySnapshot")
    ],
    targets: [
        .target(
            name: "TheGoods",
            path: "Sources/TheGoods"
        ),
        // Swift implementation of InsideMan
        .target(
            name: "InsideMan",
            dependencies: [
                "TheGoods",
                .product(name: "AccessibilitySnapshotParser", package: "AccessibilitySnapshot")
            ],
            path: "Sources/InsideMan"
        ),
        // Objective-C loader that triggers auto-start via +load
        .target(
            name: "InsideManLoader",
            dependencies: ["InsideMan"],
            path: "Sources/InsideManLoader",
            publicHeadersPath: "include"
        ),
        .target(
            name: "Wheelman",
            dependencies: ["TheGoods"],
            path: "Sources/Wheelman"
        ),
        .testTarget(
            name: "TheGoodsTests",
            dependencies: ["TheGoods"],
            path: "Tests/TheGoodsTests"
        )
    ]
)

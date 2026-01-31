// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AccessibilityBridgeProtocol",
    platforms: [
        .iOS(.v15),
        .macOS(.v13)
    ],
    products: [
        .library(name: "AccessibilityBridgeProtocol", targets: ["AccessibilityBridgeProtocol"]),
        .library(name: "AccessibilityBridgeServer", targets: ["AccessibilityBridgeServer"])
    ],
    dependencies: [
        .package(path: "../AccessibilitySnapshot")
    ],
    targets: [
        .target(name: "AccessibilityBridgeProtocol"),
        .target(
            name: "AccessibilityBridgeServer",
            dependencies: [
                "AccessibilityBridgeProtocol",
                .product(name: "AccessibilitySnapshotParser", package: "AccessibilitySnapshot")
            ]
        )
    ]
)

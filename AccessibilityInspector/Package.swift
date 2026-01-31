// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AccessibilityInspector",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../AccessibilityBridgeProtocol")
    ],
    targets: [
        .executableTarget(
            name: "AccessibilityInspector",
            dependencies: [
                .product(name: "AccessibilityBridgeProtocol", package: "AccessibilityBridgeProtocol")
            ],
            path: "AccessibilityInspector",
            exclude: ["CLI"]
        ),
        .executableTarget(
            name: "a11y-inspect",
            dependencies: [
                .product(name: "AccessibilityBridgeProtocol", package: "AccessibilityBridgeProtocol")
            ],
            path: "AccessibilityInspector/CLI"
        )
    ]
)

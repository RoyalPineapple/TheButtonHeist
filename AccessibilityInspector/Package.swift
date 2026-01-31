// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AccessibilityInspector",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../AccessibilityBridgeProtocol"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
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
                .product(name: "AccessibilityBridgeProtocol", package: "AccessibilityBridgeProtocol"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "AccessibilityInspector/CLI",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        )
    ]
)

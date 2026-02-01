// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AccraCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AccraCore", targets: ["AccraCore"]),
        .library(name: "AccraHost", targets: ["AccraHost"]),
        .library(name: "AccraClient", targets: ["AccraClient"])
    ],
    dependencies: [
        .package(path: "../AccessibilitySnapshot")
    ],
    targets: [
        .target(
            name: "AccraCore",
            path: "Sources/AccraCore"
        ),
        .target(
            name: "AccraHost",
            dependencies: [
                "AccraCore",
                .product(name: "AccessibilitySnapshotParser", package: "AccessibilitySnapshot")
            ],
            path: "Sources/AccraHost"
        ),
        .target(
            name: "AccraClient",
            dependencies: ["AccraCore"],
            path: "Sources/AccraClient"
        )
    ]
)

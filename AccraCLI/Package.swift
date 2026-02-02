// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AccraCLI",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../AccraCore"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "accra",
            dependencies: [
                .product(name: "AccraCore", package: "AccraCore"),
                .product(name: "AccraClient", package: "AccraCore"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "AccraCLITests",
            dependencies: [
                .product(name: "AccraCore", package: "AccraCore")
            ],
            path: "Tests"
        )
    ]
)

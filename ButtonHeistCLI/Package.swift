// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ButtonHeistCLI",
    platforms: [
        .macOS(.v14)
    ],
    dependencies: [
        .package(path: "../ButtonHeist"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
    ],
    targets: [
        .executableTarget(
            name: "buttonheist",
            dependencies: [
                .product(name: "TheGoods", package: "ButtonHeist"),
                .product(name: "Wheelman", package: "ButtonHeist"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ]
        ),
        .testTarget(
            name: "ButtonHeistCLITests",
            dependencies: [
                .product(name: "TheGoods", package: "ButtonHeist")
            ],
            path: "Tests"
        )
    ]
)

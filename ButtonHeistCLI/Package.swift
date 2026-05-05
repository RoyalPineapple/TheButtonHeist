// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ButtonHeistCLI",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "buttonheist", targets: ["ButtonHeistCLIExe"])
    ],
    dependencies: [
        .package(path: "../ButtonHeist"),
        .package(url: "https://github.com/apple/swift-argument-parser", .upToNextMinor(from: "1.7.0"))
    ],
    targets: [
        .executableTarget(
            name: "ButtonHeistCLIExe",
            dependencies: [
                .product(name: "ButtonHeist", package: "ButtonHeist"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .unsafeFlags(["-parse-as-library", "-warnings-as-errors"])
            ]
        ),
        .testTarget(
            name: "ButtonHeistCLITests",
            dependencies: [
                .target(name: "ButtonHeistCLIExe"),
                .product(name: "ButtonHeist", package: "ButtonHeist")
            ],
            path: "Tests",
            swiftSettings: [.swiftLanguageMode(.v6), .unsafeFlags(["-warnings-as-errors"])]
        )
    ]
)

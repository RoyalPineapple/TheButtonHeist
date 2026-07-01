// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ButtonHeistDSLImportContract",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "buttonheist-dsl-import-contract", targets: ["ButtonHeistDSLImportContract"]),
    ],
    dependencies: [
        .package(name: "ButtonHeist", path: "../../.."),
    ],
    targets: [
        .executableTarget(
            name: "ButtonHeistDSLImportContract",
            dependencies: [
                .product(name: "ButtonHeistDSL", package: "ButtonHeist"),
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
